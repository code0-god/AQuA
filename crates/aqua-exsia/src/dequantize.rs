use crate::{ExsiaError, ExsiaOutput, QuantizedValues};
use aqua_runtime::{ActivationExecutionPlan, HostTensor};

/// Reconstructs a lossy Q-only dense activation emulation for an execution plan.
///
/// This path uses `q * 2^theta` for each planned stripe and deliberately
/// excludes residuals. It is not the future residual-aware canonical RaCo
/// reconstruction.
pub fn dequantize_dense(
    output: &ExsiaOutput,
    plan: &ActivationExecutionPlan,
) -> Result<HostTensor, ExsiaError> {
    plan.validate_tensor_shape(&output.shape)?;

    let matrix = plan.matrix();
    let expected_element_count = matrix.element_count()?;
    let actual_element_count = output.quantized.len();
    if actual_element_count != expected_element_count {
        return Err(ExsiaError::InvalidOutputElementCount {
            expected: expected_element_count,
            actual: actual_element_count,
        });
    }

    let expected_theta_count = plan.stripe_count();
    let actual_theta_count = output.stripe_theta.len();
    if actual_theta_count != expected_theta_count {
        return Err(ExsiaError::InvalidStripeThetaCount {
            expected: expected_theta_count,
            actual: actual_theta_count,
        });
    }

    let logical_k = matrix.k();
    let mut dense = Vec::with_capacity(expected_element_count);

    for (stripe, &theta) in plan.stripes().iter().zip(&output.stripe_theta) {
        let scale = 2.0_f32.powi(i32::from(theta));
        let start = stripe.row_start() * logical_k;
        let end = stripe.row_end() * logical_k;

        match &output.quantized {
            QuantizedValues::I4(values) | QuantizedValues::I8(values) => {
                dense.extend(values[start..end].iter().map(|&q| f32::from(q) * scale));
            }
            QuantizedValues::I16(values) => {
                dense.extend(values[start..end].iter().map(|&q| f32::from(q) * scale));
            }
        }
    }

    Ok(HostTensor::f32(output.shape.clone(), dense)?)
}

#[cfg(test)]
mod tests {
    use super::dequantize_dense;
    use crate::{ExsiaError, ExsiaOutput, QuantizedValues, ResidualEvent, ResidualStripe};
    use aqua_runtime::{ActivationExecutionPlan, ActivationMatrixShape, StripePlan};

    fn plan(shape: &[usize], ranges: &[(usize, usize)]) -> ActivationExecutionPlan {
        let matrix = ActivationMatrixShape::from_tensor_shape(shape).expect("valid matrix shape");
        let stripes = ranges
            .iter()
            .copied()
            .enumerate()
            .map(|(index, (row_start, row_end))| StripePlan::new(index, row_start, row_end))
            .collect();

        ActivationExecutionPlan::new(matrix, stripes).expect("valid execution plan")
    }

    fn residual_stripe(
        stripe_index: usize,
        row_start: usize,
        row_count: usize,
        logical_k: usize,
    ) -> ResidualStripe {
        ResidualStripe::with_capacity(stripe_index, row_start, row_count, logical_k, 0)
    }

    #[test]
    fn excludes_residuals_from_q_only_dense_dequantization() {
        let mut residual = residual_stripe(0, 0, 1, 1);
        residual.push(ResidualEvent::new(0, 0, 7));
        let output = ExsiaOutput {
            quantized: QuantizedValues::I8(vec![1]),
            stripe_theta: vec![0],
            residual_stripes: vec![residual],
            shape: vec![1, 1],
        };

        let dense =
            dequantize_dense(&output, &plan(&[1, 1], &[(0, 1)])).expect("valid Q-only output");

        assert_eq!(dense.desc.shape, vec![1, 1]);
        assert_eq!(dense.data, vec![1.0]);
    }

    #[test]
    fn rejects_quantized_element_count_mismatch() {
        let output = ExsiaOutput {
            quantized: QuantizedValues::I8(vec![1]),
            stripe_theta: vec![0],
            residual_stripes: vec![],
            shape: vec![1, 2],
        };

        assert!(matches!(
            dequantize_dense(&output, &plan(&[1, 2], &[(0, 1)])),
            Err(ExsiaError::InvalidOutputElementCount {
                expected: 2,
                actual: 1,
            })
        ));
    }

    #[test]
    fn rejects_stripe_theta_count_mismatch() {
        let output = ExsiaOutput {
            quantized: QuantizedValues::I8(vec![1, 2]),
            stripe_theta: vec![0],
            residual_stripes: vec![],
            shape: vec![2, 1],
        };

        assert!(matches!(
            dequantize_dense(&output, &plan(&[2, 1], &[(0, 1), (1, 2)])),
            Err(ExsiaError::InvalidStripeThetaCount {
                expected: 2,
                actual: 1,
            })
        ));
    }

    #[test]
    fn preserves_partial_shape_multiple_stripe_widths_and_row_order() {
        let output = ExsiaOutput {
            quantized: QuantizedValues::I8(vec![1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12]),
            stripe_theta: vec![0, 1, -1],
            residual_stripes: vec![],
            shape: vec![2, 2, 3],
        };

        let dense = dequantize_dense(&output, &plan(&[2, 2, 3], &[(0, 1), (1, 3), (3, 4)]))
            .expect("valid multi-stripe output");

        assert_eq!(dense.desc.shape, vec![2, 2, 3]);
        assert_eq!(
            dense.data,
            vec![1.0, 2.0, 3.0, 8.0, 10.0, 12.0, 14.0, 16.0, 18.0, 5.0, 5.5, 6.0]
        );
    }

    #[test]
    fn dequantizes_i4_i8_and_i16_values() {
        let cases = [
            (QuantizedValues::I4(vec![-8, 7]), vec![-4.0, 3.5]),
            (QuantizedValues::I8(vec![-4, 6]), vec![-2.0, 3.0]),
            (
                QuantizedValues::I16(vec![-32_768, 32_767]),
                vec![-16_384.0, 16_383.5],
            ),
        ];

        for (quantized, expected) in cases {
            let output = ExsiaOutput {
                quantized,
                stripe_theta: vec![-1],
                residual_stripes: vec![],
                shape: vec![1, 2],
            };

            let dense = dequantize_dense(&output, &plan(&[1, 2], &[(0, 1)]))
                .expect("valid precision output");

            assert_eq!(dense.desc.shape, vec![1, 2]);
            assert_eq!(dense.data, expected);
        }
    }
}
