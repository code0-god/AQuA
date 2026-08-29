use super::{
    execute, execution_plan, host_tensor, ExecutionPlanError, ExsiaConfig, ExsiaError, ExsiaInput,
    ExsiaPrecision, QuantizedValues, ReferenceExsia,
};

#[test]
fn executes_single_row_single_stripe_without_residual() {
    let output = execute(&[32], vec![1.0; 32], ExsiaPrecision::I8, &[(0, 1)]);

    assert_eq!(output.quantized, QuantizedValues::I8(vec![64; 32]));
    assert_eq!(output.precision(), ExsiaPrecision::I8);
    assert_eq!(output.stripe_theta, vec![-6]);
    assert_eq!(output.residual_stripes.len(), 1);
    assert!(output.residual_stripes[0].is_empty());
    assert_eq!(output.shape, vec![32]);
}

#[test]
fn emits_tensor_level_promoted_block_residuals() {
    let values = [vec![8.0; 32], vec![2.0; 32]].concat();
    let output = execute(&[64], values, ExsiaPrecision::I8, &[(0, 1)]);

    assert_eq!(
        output.quantized,
        QuantizedValues::I8([vec![127_i8; 32], vec![64_i8; 32]].concat())
    );
    assert_eq!(output.stripe_theta, vec![-5]);

    let events = output.residual_stripes[0].events();
    assert_eq!(events.len(), 32);

    for (k, event) in events.iter().enumerate() {
        assert_eq!(
            (event.local_row(), event.k(), event.residual()),
            (0, k, 129)
        );
    }
}

#[test]
fn quantizes_all_zero_tensor_without_residuals() {
    let output = execute(&[64], vec![0.0; 64], ExsiaPrecision::I8, &[(0, 1)]);

    assert_eq!(output.quantized, QuantizedValues::I8(vec![0; 64]));
    assert_eq!(output.stripe_theta, vec![-6]);
    assert!(output.residual_stripes[0].is_empty());
}

#[test]
fn preserves_requested_precision_variant() {
    let cases = [
        (ExsiaPrecision::I4, QuantizedValues::I4(vec![4_i8; 32])),
        (ExsiaPrecision::I8, QuantizedValues::I8(vec![64_i8; 32])),
        (
            ExsiaPrecision::I16,
            QuantizedValues::I16(vec![16_384_i16; 32]),
        ),
    ];

    for (precision, expected) in cases {
        let output = execute(&[32], vec![1.0; 32], precision, &[(0, 1)]);

        assert_eq!(output.quantized, expected);
        assert_eq!(output.precision(), precision);
    }
}

#[test]
fn rejects_plan_shape_before_running_algorithms() {
    let tensor = host_tensor(&[2, 32], vec![0.0; 64]);
    let input =
        ExsiaInput::new(&tensor, ExsiaConfig::new(ExsiaPrecision::I8)).expect("valid ExSIA input");
    let plan = execution_plan(&[3, 32], &[(0, 3)]);

    let result = ReferenceExsia::new().execute(&input, &plan);

    assert!(matches!(
        result,
        Err(ExsiaError::InvalidExecutionPlan(
            ExecutionPlanError::MatrixShapeMismatch {
                expected_rows: 3,
                expected_k: 32,
                actual_rows: 2,
                actual_k: 32,
            }
        ))
    ));
}

#[test]
fn repeats_execution_deterministically() {
    let tensor = host_tensor(&[64], [vec![8.0; 32], vec![2.0; 32]].concat());
    let input =
        ExsiaInput::new(&tensor, ExsiaConfig::new(ExsiaPrecision::I8)).expect("valid ExSIA input");
    let plan = execution_plan(&[64], &[(0, 1)]);
    let reference = ReferenceExsia::new();

    let first = reference
        .execute(&input, &plan)
        .expect("first reference execution");
    let second = reference
        .execute(&input, &plan)
        .expect("second reference execution");

    assert_eq!(first, second);
}
