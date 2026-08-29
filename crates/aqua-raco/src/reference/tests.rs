use super::{execute_raco_reference, oracle::direct_correction};
use crate::DenseWeightCodes;
use aqua_exsia::{ExsiaConfig, ExsiaInput, ExsiaPrecision, ReferenceExsia, ResidualStripe};
use aqua_runtime::{ActivationExecutionPlan, ActivationMatrixShape, HostTensor, StripePlan};

fn residual_stripe(shape: &[usize], values: Vec<f32>, precision: ExsiaPrecision) -> ResidualStripe {
    let tensor = HostTensor::f32(shape.to_vec(), values).expect("valid tensor");
    let input = ExsiaInput::new(&tensor, ExsiaConfig::new(precision)).expect("valid ExSIA input");
    let matrix = ActivationMatrixShape::from_tensor_shape(shape).expect("valid matrix shape");
    let plan = ActivationExecutionPlan::new(matrix, vec![StripePlan::new(0, 0, matrix.rows())])
        .expect("valid execution plan");

    ReferenceExsia::new()
        .execute(&input, &plan)
        .expect("valid ExSIA execution")
        .residual_stripes
        .into_iter()
        .next()
        .expect("one stripe")
}

fn assert_parity(
    residuals: &ResidualStripe,
    precision: ExsiaPrecision,
    weights: &DenseWeightCodes<'_>,
) {
    let direct = direct_correction(residuals, weights).expect("direct correction");
    let raco = execute_raco_reference(residuals, precision, weights).expect("RaCo reference");

    assert_eq!(raco.correction().values(), direct);
}

#[test]
fn direct_equals_raco_single_event() {
    let mut values = vec![1.0; 33];
    values[0] = 8.0;
    let residuals = residual_stripe(&[1, 33], values, ExsiaPrecision::I8);
    let codes = vec![1; 33];
    let weights = DenseWeightCodes::new(&codes, 33, 1).expect("valid weights");

    assert_eq!(residuals.len(), 1);
    assert_parity(&residuals, ExsiaPrecision::I8, &weights);
}

#[test]
fn direct_equals_raco_multiple_events_same_block() {
    let mut values = vec![1.0; 33];
    values[0] = 8.0;
    values[7] = 8.0;
    let residuals = residual_stripe(&[1, 33], values, ExsiaPrecision::I8);
    let codes = vec![1; 33];
    let weights = DenseWeightCodes::new(&codes, 33, 1).expect("valid weights");

    assert_eq!(residuals.len(), 2);
    assert_parity(&residuals, ExsiaPrecision::I8, &weights);
}

#[test]
fn direct_equals_raco_multiple_rows() {
    let mut row = vec![1.0; 33];
    row[0] = 8.0;
    let residuals = residual_stripe(&[2, 33], [row.clone(), row].concat(), ExsiaPrecision::I8);
    let codes = vec![1; 33];
    let weights = DenseWeightCodes::new(&codes, 33, 1).expect("valid weights");

    assert_parity(&residuals, ExsiaPrecision::I8, &weights);
}

#[test]
fn direct_equals_raco_multiple_blocks() {
    let mut values = vec![1.0; 65];
    values[0] = 8.0;
    values[32] = 8.0;
    let residuals = residual_stripe(&[1, 65], values, ExsiaPrecision::I8);
    let codes = vec![1; 65];
    let weights = DenseWeightCodes::new(&codes, 65, 1).expect("valid weights");

    assert_eq!(residuals.len(), 2);
    assert_parity(&residuals, ExsiaPrecision::I8, &weights);
}

#[test]
fn direct_equals_raco_sparse_lane_ids() {
    let mut values = vec![1.0; 33];
    values[0] = 128.0;
    let residuals = residual_stripe(&[1, 33], values, ExsiaPrecision::I4);
    let codes = vec![1; 33];
    let weights = DenseWeightCodes::new(&codes, 33, 1).expect("valid weights");
    let result =
        execute_raco_reference(&residuals, ExsiaPrecision::I4, &weights).expect("RaCo reference");

    assert_eq!(
        result.work().expect("work").blocks()[0].active_lane_ids(),
        &[0, 2]
    );
    assert_eq!(
        result.correction().values(),
        direct_correction(&residuals, &weights).expect("direct correction")
    );
}

#[test]
fn direct_equals_raco_i4_i8_and_i16() {
    for precision in [ExsiaPrecision::I4, ExsiaPrecision::I8, ExsiaPrecision::I16] {
        let mut values = vec![1.0; 33];
        values[0] = 8.0;
        let residuals = residual_stripe(&[1, 33], values, precision);
        let codes = vec![1; 33];
        let weights = DenseWeightCodes::new(&codes, 33, 1).expect("valid weights");

        assert_parity(&residuals, precision, &weights);
    }
}

#[test]
fn direct_equals_raco_with_negative_residuals_and_weights() {
    let mut values = vec![1.0; 33];
    values[0] = -8.0;
    let residuals = residual_stripe(&[1, 33], values, ExsiaPrecision::I8);
    let codes = vec![-3; 33];
    let weights = DenseWeightCodes::new(&codes, 33, 1).expect("valid weights");

    assert!(residuals.iter().any(|event| event.residual() < 0));
    assert_parity(&residuals, ExsiaPrecision::I8, &weights);
}

#[test]
fn empty_residual_returns_zero_correction() {
    let residuals = residual_stripe(&[1, 32], vec![1.0; 32], ExsiaPrecision::I8);
    let codes = vec![1; 64];
    let weights = DenseWeightCodes::new(&codes, 32, 2).expect("valid weights");

    let result =
        execute_raco_reference(&residuals, ExsiaPrecision::I8, &weights).expect("RaCo reference");

    assert!(result.work().is_none());
    assert!(result.compressed().is_none());
    assert_eq!(result.correction().values(), &[0, 0]);
}

#[test]
fn same_input_produces_identical_work_and_output() {
    let mut values = vec![1.0; 33];
    values[0] = 8.0;
    let residuals = residual_stripe(&[1, 33], values, ExsiaPrecision::I8);
    let codes = vec![1; 33];
    let weights = DenseWeightCodes::new(&codes, 33, 1).expect("valid weights");

    let first =
        execute_raco_reference(&residuals, ExsiaPrecision::I8, &weights).expect("first execution");
    let second =
        execute_raco_reference(&residuals, ExsiaPrecision::I8, &weights).expect("second execution");

    assert_eq!(first, second);
}
