use crate::{ExsiaPrecision, ResidualStripe};

/// Logical quantized activation values produced by ExSIA.
///
/// I4 values are stored as `i8` in the software reference.
/// Their valid logical range is still -8..=7.
///
/// Physical nibble packing belongs to the hardware/transport boundary,
/// not to the canonical ExSIA algorithm.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum QuantizedValues {
    I4(Vec<i8>),   // 논리적 I4. 실제 저장 container는 Vec<i8>.
    I8(Vec<i8>),   // I8 값은 Vec<i8>에 저장.
    I16(Vec<i16>), // I16 값은 Vec<i16>에 저장.
}

impl QuantizedValues {
    pub(crate) fn with_capacity(precision: ExsiaPrecision, capacity: usize) -> Self {
        match precision {
            // precision enum variant에 따라 다른 Self 생성.
            ExsiaPrecision::I4 => Self::I4(Vec::with_capacity(capacity)),
            ExsiaPrecision::I8 => Self::I8(Vec::with_capacity(capacity)),
            ExsiaPrecision::I16 => Self::I16(Vec::with_capacity(capacity)),
        }
    }

    pub fn precision(&self) -> ExsiaPrecision {
        match self {
            Self::I4(_) => ExsiaPrecision::I4, // `_`: 내부 Vec 값은 사용하지 않음.
            Self::I8(_) => ExsiaPrecision::I8,
            Self::I16(_) => ExsiaPrecision::I16,
        }
    }

    pub fn len(&self) -> usize {
        match self {
            Self::I4(values) => values.len(), // variant 내부 Vec을 values라는 이름으로 꺼냄.
            Self::I8(values) => values.len(),
            Self::I16(values) => values.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0 // element가 0개인지 검사.
    }

    /// Appends one already-clipped i32 value.
    ///
    /// The caller must guarantee that `value` is inside the valid
    /// range for this quantized precision.
    pub(crate) fn push_clipped(&mut self, value: i32) {
        match self {
            Self::I4(values) => {
                // values: &mut Vec<i8>
                debug_assert!((-8..=7).contains(&value));
                // inclusive range -8부터 7까지 검사.
                values.push(value as i8); // 범위가 맞다는 전제하에 i32 -> i8 변환.
            }

            Self::I8(values) => {
                debug_assert!((-128..=127).contains(&value));
                values.push(value as i8);
            }

            Self::I16(values) => {
                debug_assert!((-32_768..=32_767).contains(&value));
                values.push(value as i16);
            }
        }
    }

    /// Appends another quantized vector with the same precision.
    pub(crate) fn append(&mut self, other: &mut Self) {
        match (self, other) {
            // 두 enum을 동시에 pattern matching.
            (Self::I4(dst), Self::I4(src)) => dst.append(src), // src의 모든 원소를 dst 뒤로 이동.
            (Self::I8(dst), Self::I8(src)) => dst.append(src),
            (Self::I16(dst), Self::I16(src)) => dst.append(src),

            _ => {
                // 위 pattern과 맞지 않는 모든 경우.
                panic!("cannot append quantized values with different precisions");
            }
        }
    }
}

/// Final software-visible ExSIA result.
///
/// The dense activation values are represented at the selected target
/// precision. Stripe theta values and stripe-scoped residuals are retained
/// separately because they are required to reconstruct the wide integer
/// representation.
///
/// Invariants:
/// - `stripe_theta.len() == residual_stripes.len()`
/// - `residual_stripes[i].stripe_index() == i`
/// - `quantized.len()` equals the original logical element count
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ExsiaOutput {
    pub quantized: QuantizedValues, // 최종 dense quantized activation.

    /// Quantization exponent θ_s for each stripe.
    pub stripe_theta: Vec<i16>, // stripe마다 하나의 quantization exponent.

    /// Stripe-scoped residual events consumed by the future RACO path.
    pub residual_stripes: Vec<ResidualStripe>,

    /// Original logical activation shape.
    pub shape: Vec<usize>, // 원본 tensor의 logical shape.
}

impl ExsiaOutput {
    pub fn len(&self) -> usize {
        self.quantized.len() // quantized 값 개수를 그대로 반환.
    }

    pub fn is_empty(&self) -> bool {
        self.quantized.is_empty() // quantized vector가 비었는지 위임.
    }

    pub fn precision(&self) -> ExsiaPrecision {
        self.quantized.precision() // 실제 QuantizedValues variant에서 precision 확인.
    }
}

#[cfg(test)]
mod tests {
    use super::{ExsiaOutput, QuantizedValues};

    use crate::{ExsiaPrecision, ResidualStripe};

    #[test]
    fn stores_i4_as_logical_i8_values() {
        let mut values = QuantizedValues::with_capacity(ExsiaPrecision::I4, 3);

        values.push_clipped(-8);
        values.push_clipped(0);
        values.push_clipped(7);

        assert_eq!(values, QuantizedValues::I4(vec![-8, 0, 7]));

        assert_eq!(values.precision(), ExsiaPrecision::I4);
    }

    #[test]
    fn stores_i8_values() {
        let mut values = QuantizedValues::with_capacity(ExsiaPrecision::I8, 2);

        values.push_clipped(-128);
        values.push_clipped(127);

        assert_eq!(values, QuantizedValues::I8(vec![-128, 127]));
    }

    #[test]
    fn stores_i16_values() {
        let mut values = QuantizedValues::with_capacity(ExsiaPrecision::I16, 2);

        values.push_clipped(-32_768);
        values.push_clipped(32_767);

        assert_eq!(values, QuantizedValues::I16(vec![-32_768, 32_767]));
    }

    #[test]
    fn appends_same_precision_values() {
        let mut lhs = QuantizedValues::I8(vec![1, 2]);

        let mut rhs = QuantizedValues::I8(vec![3, 4]);

        lhs.append(&mut rhs);

        assert_eq!(lhs, QuantizedValues::I8(vec![1, 2, 3, 4]));

        assert!(rhs.is_empty());
    }

    #[test]
    fn output_tracks_quantized_and_stripe_contracts() {
        // Given
        let output = ExsiaOutput {
            quantized: QuantizedValues::I8(vec![0; 66]),
            stripe_theta: vec![-6, -5],
            residual_stripes: vec![
                ResidualStripe::with_capacity(0, 0, 1, 33, 0),
                ResidualStripe::with_capacity(1, 1, 1, 33, 0),
            ],
            shape: vec![2, 33],
        };

        // When
        let contract = (
            output.precision(),
            output.len(),
            output.stripe_theta.len(),
            output.residual_stripes.len(),
            output.shape.as_slice(),
        );

        // Then
        assert_eq!(contract, (ExsiaPrecision::I8, 66, 2, 2, [2, 33].as_slice()));
        assert!(!output.is_empty());
    }
}
