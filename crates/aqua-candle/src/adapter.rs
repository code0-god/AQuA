use aqua_protocol::AquaDType;
use aqua_runtime::{HostTensor, RuntimeError};
use candle_core::{DType, Device, Tensor};
use std::{error::Error, fmt};

/// Copies a Candle floating-point tensor to CPU and canonicalizes it as F32.
pub fn tensor_to_host(tensor: &Tensor) -> Result<HostTensor, AdapterError> {
    if !tensor.dtype().is_float() {
        return Err(AdapterError::UnsupportedDType(tensor.dtype()));
    }

    let cpu = if tensor.device().is_cpu() {
        tensor.clone()
    } else {
        tensor.to_device(&Device::Cpu)?
    };
    let normalized = if cpu.dtype() == DType::F32 {
        cpu
    } else {
        cpu.to_dtype(DType::F32)?
    };

    let values = normalized.contiguous()?.flatten_all()?.to_vec1::<f32>()?;
    Ok(HostTensor::f32(tensor.dims().to_vec(), values)?)
}

pub fn host_to_tensor(host: &HostTensor) -> Result<Tensor, AdapterError> {
    host_to_tensor_on(host, &Device::Cpu)
}

pub fn host_to_tensor_on(host: &HostTensor, device: &Device) -> Result<Tensor, AdapterError> {
    host.validate()?;
    if host.desc.dtype != AquaDType::F32 {
        return Err(AdapterError::UnsupportedHostDType(host.desc.dtype));
    }
    Ok(Tensor::from_vec(
        host.data.clone(),
        host.desc.shape.clone(),
        device,
    )?)
}

#[derive(Debug)]
pub enum AdapterError {
    Candle(candle_core::Error),
    Runtime(RuntimeError),
    UnsupportedDType(DType),
    UnsupportedHostDType(AquaDType),
}

impl fmt::Display for AdapterError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Candle(error) => error.fmt(formatter),
            Self::Runtime(error) => error.fmt(formatter),
            Self::UnsupportedDType(dtype) => {
                write!(formatter, "unsupported Candle dtype: {dtype:?}")
            }
            Self::UnsupportedHostDType(dtype) => {
                write!(formatter, "unsupported host dtype: {dtype:?}")
            }
        }
    }
}

impl Error for AdapterError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::Candle(error) => Some(error),
            Self::Runtime(error) => Some(error),
            Self::UnsupportedDType(_) | Self::UnsupportedHostDType(_) => None,
        }
    }
}

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
