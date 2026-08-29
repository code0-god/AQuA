use aqua_candle::{host_to_tensor, tensor_to_host, AdapterError};
use aqua_protocol::AquaDType;
use aqua_runtime::RuntimeError;
use candle_core::{DType, Device, Tensor};
use std::error::Error;

#[test]
fn chains_wrapped_adapter_error_source() {
    let error = AdapterError::from(RuntimeError::ElementCountMismatch {
        expected: 2,
        actual: 1,
    });

    assert!(error.source().is_some());
}

#[test]
fn preserves_contiguous_cpu_f32_tensor() -> Result<(), Box<dyn std::error::Error>> {
    let source = Tensor::from_vec(vec![0.0_f32, 1.0, -2.0, 4.0], (2, 2), &Device::Cpu)?;

    let host = tensor_to_host(&source)?;

    assert_eq!(host.desc.dtype, AquaDType::F32);
    assert_eq!(host.desc.shape, [2, 2]);
    assert_eq!(host.desc.len, 4);
    assert_eq!(host.data, [0.0, 1.0, -2.0, 4.0]);
    Ok(())
}

#[test]
fn round_trips_cpu_f32_tensor() -> Result<(), Box<dyn std::error::Error>> {
    let source = Tensor::from_vec(
        vec![0.0_f32, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
        (2, 4),
        &Device::Cpu,
    )?
    .transpose(0, 1)?;

    let host = tensor_to_host(&source)?;
    assert_eq!(host.desc.dtype, AquaDType::F32);
    assert_eq!(host.desc.shape, [4, 2]);
    assert_eq!(host.desc.len, 8);
    assert_eq!(host.data, [0.0, 4.0, 1.0, 5.0, 2.0, 6.0, 3.0, 7.0]);

    let restored = host_to_tensor(&host)?;
    assert_eq!(
        source.flatten_all()?.to_vec1::<f32>()?,
        restored.flatten_all()?.to_vec1::<f32>()?
    );
    Ok(())
}

#[test]
fn canonicalizes_f16_to_host_f32() -> Result<(), Box<dyn std::error::Error>> {
    let source = Tensor::from_vec(vec![0.0_f32, 1.0, 2.0, 3.0], (2, 2), &Device::Cpu)?
        .to_dtype(DType::F16)?;

    let host = tensor_to_host(&source)?;

    assert_eq!(host.desc.dtype, AquaDType::F32);
    assert_eq!(host.desc.shape, [2, 2]);
    assert_eq!(host.data, [0.0, 1.0, 2.0, 3.0]);

    Ok(())
}

#[test]
fn canonicalizes_bf16_to_host_f32() -> Result<(), Box<dyn std::error::Error>> {
    let source = Tensor::from_vec(vec![0.0_f32, 1.0, -2.0, 4.0], (2, 2), &Device::Cpu)?
        .to_dtype(DType::BF16)?;

    let host = tensor_to_host(&source)?;

    assert_eq!(host.desc.dtype, AquaDType::F32);
    assert_eq!(host.desc.shape, [2, 2]);
    assert_eq!(host.data, [0.0, 1.0, -2.0, 4.0]);
    Ok(())
}

#[test]
fn canonicalizes_f64_to_host_f32() -> Result<(), Box<dyn std::error::Error>> {
    let source = Tensor::from_vec(vec![0.0_f64, 1.0, -2.0, 4.0], (2, 2), &Device::Cpu)?;

    let host = tensor_to_host(&source)?;

    assert_eq!(host.desc.dtype, AquaDType::F32);
    assert_eq!(host.desc.shape, [2, 2]);
    assert_eq!(host.data, [0.0, 1.0, -2.0, 4.0]);
    Ok(())
}

#[test]
fn canonicalizes_non_contiguous_f16_in_logical_order() -> Result<(), Box<dyn std::error::Error>> {
    let source = Tensor::from_vec(vec![0.0_f32, 1.0, 2.0, 3.0, 4.0, 5.0], (2, 3), &Device::Cpu)?
        .to_dtype(DType::F16)?
        .transpose(0, 1)?;

    let host = tensor_to_host(&source)?;

    assert_eq!(host.desc.dtype, AquaDType::F32);
    assert_eq!(host.desc.shape, [3, 2]);
    assert_eq!(host.data, [0.0, 3.0, 1.0, 4.0, 2.0, 5.0]);
    Ok(())
}

#[test]
fn rejects_integer_activation() -> Result<(), Box<dyn std::error::Error>> {
    let source = Tensor::from_vec(vec![0_i16, 1, -2, 4], (2, 2), &Device::Cpu)?;

    assert!(matches!(
        tensor_to_host(&source),
        Err(AdapterError::UnsupportedDType(DType::I16))
    ));
    Ok(())
}
