use aqua_candle::{
    dense_q_only_aqua_device, host_to_tensor_on, tensor_to_host, FixedStripePlanner,
};
use aqua_exsia::{ExsiaConfig, ExsiaPrecision};
use aqua_runtime::HostTensor;
use candle_core::{DType, Device, Tensor};
use std::num::NonZeroUsize;

fn stripe_rows(rows: usize) -> NonZeroUsize {
    NonZeroUsize::new(rows).expect("non-zero stripe rows")
}

fn i8_config() -> ExsiaConfig {
    ExsiaConfig::new(ExsiaPrecision::I8)
}

#[test]
fn planner_uses_one_partial_stripe_for_191_rows_with_320_row_capacity(
) -> Result<(), Box<dyn std::error::Error>> {
    let plan = FixedStripePlanner::new(stripe_rows(320)).plan(&[191, 2])?;

    assert_eq!(plan.matrix().rows(), 191);
    assert_eq!(plan.matrix().k(), 2);
    assert_eq!(plan.stripe_count(), 1);
    assert_eq!(plan.stripes()[0].row_start(), 0);
    assert_eq!(plan.stripes()[0].row_end(), 191);
    Ok(())
}

#[test]
fn dense_q_only_device_multiplies_191_rows_with_a_320_row_stripe(
) -> Result<(), Box<dyn std::error::Error>> {
    let device = dense_q_only_aqua_device(0, i8_config(), stripe_rows(320))?;
    let lhs = Tensor::from_vec(vec![1.0_f32; 191 * 2], (191, 2), &device)?;
    let rhs = Tensor::from_vec(vec![1.0_f32; 2], (2, 1), &device)?;

    let output = lhs.matmul(&rhs)?.to_device(&Device::Cpu)?;

    assert_eq!(output.dims(), [191, 1]);
    assert_eq!(output.flatten_all()?.to_vec1::<f32>()?, vec![2.0; 191]);
    Ok(())
}

#[test]
fn dense_q_only_device_materializes_transposed_lhs_layout() -> Result<(), Box<dyn std::error::Error>>
{
    let device = dense_q_only_aqua_device(0, i8_config(), stripe_rows(2))?;
    let lhs = Tensor::from_vec(vec![1.0_f32, 1.25, 1.5, 1.75, 1.0, 1.25], (2, 3), &device)?
        .transpose(0, 1)?;
    let rhs = Tensor::from_vec(vec![1.0_f32, 1.0], (2, 1), &device)?;

    let output = lhs.matmul(&rhs)?.to_device(&Device::Cpu)?;

    assert_eq!(output.flatten_all()?.to_vec1::<f32>()?, [2.75, 2.25, 2.75]);
    Ok(())
}

#[test]
fn dense_q_only_device_materializes_transposed_rhs_layout() -> Result<(), Box<dyn std::error::Error>>
{
    let device = dense_q_only_aqua_device(0, i8_config(), stripe_rows(1))?;
    let lhs = Tensor::from_vec(vec![1.0_f32, 1.0], (1, 2), &device)?;
    let rhs = Tensor::from_vec(vec![2.0_f32, 3.0], (1, 2), &device)?.transpose(0, 1)?;

    let output = lhs.matmul(&rhs)?.to_device(&Device::Cpu)?;

    assert_eq!(output.to_vec2::<f32>()?, vec![vec![5.0]]);
    Ok(())
}

#[test]
fn dense_q_only_device_materializes_batched_layouts() -> Result<(), Box<dyn std::error::Error>> {
    let device = dense_q_only_aqua_device(0, i8_config(), stripe_rows(1))?;
    let lhs = Tensor::from_vec(vec![1.0_f32, 1.0, 2.0, 2.0], (2, 1, 2), &device)?;
    let rhs = Tensor::from_vec(vec![1.0_f32, 1.0, 2.0, 2.0], (2, 2, 1), &device)?;

    let output = lhs.matmul(&rhs)?.to_device(&Device::Cpu)?;

    assert_eq!(
        output.to_vec3::<f32>()?,
        vec![vec![vec![2.0]], vec![vec![8.0]]]
    );
    Ok(())
}

#[test]
fn adapter_round_trips_through_aqua_cpu_shadow() -> Result<(), Box<dyn std::error::Error>> {
    let device = dense_q_only_aqua_device(0, i8_config(), stripe_rows(4))?;
    let host = HostTensor::f32(vec![2, 2], vec![0.0, 1.0, -2.0, 4.0])?;

    let tensor = host_to_tensor_on(&host, &device)?;
    let restored = tensor_to_host(&tensor)?;

    assert!(tensor.device().is_aqua());
    assert_eq!(restored, host);
    Ok(())
}

#[test]
fn aqua_device_executes_dense_q_only_matmul() -> Result<(), Box<dyn std::error::Error>> {
    let aqua = dense_q_only_aqua_device(0, i8_config(), stripe_rows(1))?;
    let mut lhs_values = vec![8.0_f32; 32];
    lhs_values.extend(vec![2.0_f32; 32]);
    let rhs_values = vec![1.0_f32; 64];

    let lhs = Tensor::from_vec(lhs_values.clone(), (1, 64), &aqua)?;
    let rhs = Tensor::from_vec(rhs_values.clone(), (64, 1), &aqua)?;
    let aqua_result = lhs
        .matmul(&rhs)?
        .to_device(&Device::Cpu)?
        .to_vec2::<f32>()?;

    assert_eq!(aqua_result, vec![vec![191.0]]);

    let cpu_lhs = Tensor::from_vec(lhs_values, (1, 64), &Device::Cpu)?;
    let cpu_rhs = Tensor::from_vec(rhs_values, (64, 1), &Device::Cpu)?;
    let cpu_result = cpu_lhs.matmul(&cpu_rhs)?.to_vec2::<f32>()?;

    assert_eq!(cpu_result, vec![vec![320.0]]);
    assert_ne!(aqua_result, cpu_result);
    Ok(())
}

#[test]
fn dense_q_only_device_supports_float_storage_variants() -> Result<(), Box<dyn std::error::Error>> {
    let aqua = dense_q_only_aqua_device(0, i8_config(), stripe_rows(1))?;

    for dtype in [DType::F16, DType::BF16, DType::F32, DType::F64] {
        let lhs = Tensor::from_vec(vec![1.0_f32; 2], (1, 2), &aqua)?.to_dtype(dtype)?;
        let rhs = Tensor::from_vec(vec![1.0_f32; 2], (2, 1), &aqua)?.to_dtype(dtype)?;
        let output = lhs.matmul(&rhs)?;

        assert_eq!(output.dtype(), dtype);
        assert_eq!(
            output
                .to_device(&Device::Cpu)?
                .to_dtype(DType::F32)?
                .to_vec2::<f32>()?,
            vec![vec![2.0]]
        );
    }
    Ok(())
}
