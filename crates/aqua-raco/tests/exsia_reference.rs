use aqua_exsia::{
    dequantize_dense, ExsiaConfig, ExsiaInput, ExsiaPrecision, QuantizedValues, ReferenceExsia,
};
use aqua_raco::{execute_raco_reference, DenseWeightCodes};
use aqua_runtime::{ActivationExecutionPlan, ActivationMatrixShape, HostTensor, StripePlan};

#[test]
fn exsia_residual_stripe_matches_exact_raco_correction() {
    // Given
    let values = [vec![8.0; 32], vec![2.0; 32]].concat();
    let tensor = HostTensor::f32(vec![1, 64], values).expect("valid tensor");
    let input =
        ExsiaInput::new(&tensor, ExsiaConfig::new(ExsiaPrecision::I8)).expect("valid ExSIA input");
    let matrix = ActivationMatrixShape::from_tensor_shape(&[1, 64]).expect("valid matrix");
    let plan =
        ActivationExecutionPlan::new(matrix, vec![StripePlan::new(0, 0, 1)]).expect("valid plan");
    let output = ReferenceExsia::new()
        .execute(&input, &plan)
        .expect("valid ExSIA execution");
    let codes = vec![1; 64];
    let weights = DenseWeightCodes::new(&codes, 64, 1).expect("valid weights");

    // When
    let raco = execute_raco_reference(&output.residual_stripes[0], ExsiaPrecision::I8, &weights)
        .expect("valid RaCo execution");
    let dense_q = dequantize_dense(&output, &plan).expect("valid Q-only reconstruction");

    // Then
    assert_eq!(output.stripe_theta, vec![-5]);
    assert_eq!(
        output.quantized,
        QuantizedValues::I8([vec![127; 32], vec![64; 32]].concat())
    );
    assert_eq!(output.residual_stripes[0].len(), 32);
    assert!(output.residual_stripes[0]
        .iter()
        .enumerate()
        .all(|(k, event)| event.local_row() == 0 && event.k() == k && event.residual() == 129));

    let work = raco.work().expect("nonempty work");
    assert_eq!(
        work.blocks()[0].compact_k(),
        &(0_u8..32).collect::<Vec<_>>()
    );
    assert_eq!(work.blocks()[0].active_lane_ids(), &[0, 1]);
    assert_eq!(
        raco.compressed().expect("compressed output").blocks()[0].values(),
        &[-4_064, 32]
    );
    assert_eq!(raco.correction().values(), &[4_128]);

    let direct = output.residual_stripes[0]
        .iter()
        .map(|event| i64::from(event.residual()))
        .sum::<i64>();
    let dense_sum = dense_q.data.iter().sum::<f32>();
    let scale_shift =
        u32::try_from(-output.stripe_theta[0]).expect("negative theta magnitude fits u32");
    let scaled_correction = raco.correction().values()[0] / (1_i64 << scale_shift);

    assert_eq!(direct, 4_128);
    assert_eq!(dense_sum, 191.0);
    assert_eq!(scaled_correction, 129);
    assert_eq!(191_i64 + scaled_correction, 320);
}
