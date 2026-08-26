//! Accelerator execution boundary independent of Candle and transport.

use aqua_protocol::{AquaDType, TensorDesc, TensorDescError};
use std::{error::Error, fmt};

#[derive(Clone, Debug, PartialEq)]
pub struct HostTensor {
    pub desc: TensorDesc,
    pub data: Vec<f32>,
}

impl HostTensor {
    pub fn f32(shape: Vec<usize>, data: Vec<f32>) -> Result<Self, RuntimeError> {
        let desc = TensorDesc::new(AquaDType::F32, shape)?;
        let tensor = Self { desc, data };
        tensor.validate()?;
        Ok(tensor)
    }

    pub fn validate(&self) -> Result<(), RuntimeError> {
        if self.desc.dtype != AquaDType::F32 {
            return Err(RuntimeError::UnsupportedDType(self.desc.dtype));
        }
        if self.desc.len != self.data.len() {
            return Err(RuntimeError::ElementCountMismatch {
                expected: self.desc.len,
                actual: self.data.len(),
            });
        }
        Ok(())
    }
}

pub trait AquaExecutor {
    type Error: Error + Send + Sync + 'static;

    fn execute(&self, input: &HostTensor) -> Result<HostTensor, Self::Error>;
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RuntimeError {
    Descriptor(TensorDescError),
    UnsupportedDType(AquaDType),
    ElementCountMismatch { expected: usize, actual: usize },
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Descriptor(error) => error.fmt(formatter),
            Self::UnsupportedDType(dtype) => write!(formatter, "unsupported host dtype: {dtype:?}"),
            Self::ElementCountMismatch { expected, actual } => {
                write!(
                    formatter,
                    "tensor element count mismatch: expected {expected}, got {actual}"
                )
            }
        }
    }
}

impl Error for RuntimeError {}

impl From<TensorDescError> for RuntimeError {
    fn from(error: TensorDescError) -> Self {
        Self::Descriptor(error)
    }
}
