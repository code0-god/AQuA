use aqua_candle::{host_to_tensor, tensor_to_host};
use aqua_protocol::AquaDType;
use candle_core::{Device, Tensor};

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
