//! Accelerator execution boundary independent of Candle and transport.

use aqua_protocol::{AquaDType, TensorDesc, TensorDescError};
use std::{error::Error, fmt};

/// Canonical host-side activation tensor for AQuA.
///
/// Candle floating-point activations are normalized to contiguous F32
/// logical values before crossing the AQuA runtime boundary. This is an
/// accelerator input contract, not a generic tensor container.
#[derive(Clone, Debug, PartialEq)] // f32는 Eq가 아니므로 HostTensor도 Eq를 derive할 수 없음.
pub struct HostTensor {
    pub desc: TensorDesc, // tensor의 dtype, shape, element count.
    pub data: Vec<f32>,   // host가 소유하는 실제 F32 데이터.
}

impl HostTensor {
    pub fn f32(shape: Vec<usize>, data: Vec<f32>) -> Result<Self, RuntimeError> {
        // Self = HostTensor.

        let desc = TensorDesc::new(AquaDType::F32, shape)?; // TensorDescError는 From을 통해 RuntimeError로 변환됨.

        let tensor = Self { desc, data }; // field-init shorthand.

        tensor.validate()?; // Err이면 즉시 반환, Ok(())이면 계속 진행.

        Ok(tensor)
    }

    pub fn validate(&self) -> Result<(), RuntimeError> {
        // `()`는 unit type. 성공 시 별도로 반환할 값이 없다는 의미.

        self.desc.validate()?;

        if self.desc.dtype != AquaDType::F32 {
            return Err(RuntimeError::UnsupportedDType(self.desc.dtype));
        }

        if self.desc.len != self.data.len() {
            return Err(RuntimeError::ElementCountMismatch {
                expected: self.desc.len,
                actual: self.data.len(),
            });
        }

        Ok(()) // 모든 검사를 통과.
    }
}

pub trait AquaExecutor {
    // 구현체가 따라야 하는 공통 실행 interface.
    type Error: Error + Send + Sync + 'static; // associated type + trait bounds.
    type Output;

    fn execute(
        &self,
        input: &HostTensor, // ownership을 가져오지 않고 immutable borrow.
    ) -> Result<Self::Output, Self::Error>; // Self::Error는 구현체가 정한 Error 타입.
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RuntimeError {
    Descriptor(TensorDescError), // 값을 갖는 tuple-like enum variant.
    UnsupportedDType(AquaDType),

    ElementCountMismatch {
        // 이름 있는 field를 갖는 struct-like variant.
        expected: usize,
        actual: usize,
    },
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::Descriptor(error) => error.fmt(formatter), // 내부 TensorDescError의 Display를 재사용.

            Self::UnsupportedDType(dtype) => write!(formatter, "unsupported host dtype: {dtype:?}"), // {:?}: Debug formatting.

            Self::ElementCountMismatch { expected, actual } => {
                write!(
                    formatter,
                    "tensor element count mismatch: expected {expected}, got {actual}"
                )
            }
        }
    }
}

impl Error for RuntimeError {} // 표준 Rust Error trait 구현.

impl From<TensorDescError> for RuntimeError {
    // TensorDescError -> RuntimeError 변환 정의.
    fn from(error: TensorDescError) -> Self {
        Self::Descriptor(error)
    }
}

#[cfg(test)]
mod tests {
    use super::{HostTensor, RuntimeError};
    use aqua_protocol::{AquaDType, TensorDesc, TensorDescError};

    #[test]
    fn rejects_invalid_descriptor_even_when_data_matches_len() {
        let tensor = HostTensor {
            desc: TensorDesc {
                dtype: AquaDType::F32,
                shape: vec![2, 4],
                len: 7,
            },
            data: vec![0.0; 7],
        };

        assert_eq!(
            tensor.validate(),
            Err(RuntimeError::Descriptor(
                TensorDescError::ElementCountMismatch {
                    expected: 8,
                    actual: 7,
                }
            ))
        );
    }
}
