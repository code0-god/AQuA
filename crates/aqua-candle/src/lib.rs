//! Candle CPU tensor adapter for AQuA.

use aqua_protocol::AquaDType;
use aqua_runtime::{HostTensor, RuntimeError};
use candle_core::{DType, Device, DeviceLocation, Tensor};
use std::{error::Error, fmt};

pub fn tensor_to_host(tensor: &Tensor) -> Result<HostTensor, AdapterError> {
    if tensor.device().location() != DeviceLocation::Cpu {
        return Err(AdapterError::CpuTensorRequired);
    }
    if !tensor.dtype().is_float() {
        return Err(AdapterError::UnsupportedDType(tensor.dtype()));
    }

    let contiguous = tensor.contiguous()?;

    let normalized = if contiguous.dtype() == DType::F32 {
        contiguous
    } else {
        contiguous.to_dtype(DType::F32)?
    };

    let values = normalized.flatten_all()?.to_vec1::<f32>()?;
    Ok(HostTensor::f32(tensor.dims().to_vec(), values)?)
}

pub fn host_to_tensor(host: &HostTensor) -> Result<Tensor, AdapterError> {
    host.validate()?;
    if host.desc.dtype != AquaDType::F32 {
        return Err(AdapterError::UnsupportedHostDType(host.desc.dtype));
    }
    Ok(Tensor::from_vec(
        host.data.clone(),
        host.desc.shape.clone(),
        &Device::Cpu,
    )?)
}

#[derive(Debug)]
pub enum AdapterError {
    Candle(candle_core::Error),
    Runtime(RuntimeError),
    CpuTensorRequired,
    UnsupportedDType(DType),
    UnsupportedHostDType(AquaDType),
}

impl fmt::Display for AdapterError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Candle(error) => error.fmt(formatter),
            Self::Runtime(error) => error.fmt(formatter),
            Self::CpuTensorRequired => formatter.write_str("Candle tensor must be CPU-resident"),
            Self::UnsupportedDType(dtype) => {
                write!(formatter, "unsupported Candle dtype: {dtype:?}")
            }
            Self::UnsupportedHostDType(dtype) => {
                write!(formatter, "unsupported host dtype: {dtype:?}")
            }
        }
    }
}

impl Error for AdapterError {}

impl From<candle_core::Error> for AdapterError {
    fn from(error: candle_core::Error) -> Self {
        Self::Candle(error)
    }
}

impl From<RuntimeError> for AdapterError {
    fn from(error: RuntimeError) -> Self {
        Self::Runtime(error)
    }
}
