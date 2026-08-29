use crate::{ExsiaConfig, ExsiaError, EXSIA_BLOCK_SIZE};
use aqua_runtime::HostTensor;

/// validated input to ExSIA.
///
/// The underlying 'HostTensor' is already canonical contiguous F32.
/// This wrapper adds ExSIA-specific execution context without introducing
/// Candle or transport dependencies.
#[derive(Debug)] // `{:?}`로 Debug 출력 가능.
pub struct ExsiaInput<'a> {
    // `'a`: lifetime parameter.
    tensor: &'a HostTensor, // HostTensor를 소유하지 않고 `'a` 동안 빌림.
    config: ExsiaConfig,    // ExSIA 실행 설정은 직접 소유.
}

impl<'a> ExsiaInput<'a> {
    // `'a` lifetime을 사용하는 impl block.
    pub fn new(
        tensor: &'a HostTensor, // 입력 tensor를 소유하지 않고 borrow.
        config: ExsiaConfig,    // config는 함수로 ownership이 이동.
    ) -> Result<Self, ExsiaError> {
        // Self = ExsiaInput<'a>.

        tensor.validate()?; // validation 실패 시 ExsiaError로 변환되어 즉시 반환.

        if config.block_size == 0 || config.block_size > EXSIA_BLOCK_SIZE {
            return Err(ExsiaError::InvalidBlockSize {
                block_size: config.block_size,
                maximum: EXSIA_BLOCK_SIZE,
            });
        }

        Ok(Self { tensor, config }) // reference와 config를 wrapper에 저장.
    }

    pub fn tensor(&self) -> &'a HostTensor {
        self.tensor // 보관하고 있던 HostTensor reference 반환.
    }

    pub const fn config(&self) -> ExsiaConfig {
        self.config // config 값을 반환. ExsiaConfig가 Copy여야 가능.
    }

    pub fn values(&self) -> &'a [f32] {
        &self.tensor.data // Vec<f32> 전체를 읽기 전용 slice &[f32]로 반환.
    }

    pub fn shape(&self) -> &'a [usize] {
        &self.tensor.desc.shape // Vec<usize>를 읽기 전용 slice &[usize]로 반환.
    }

    pub fn len(&self) -> usize {
        self.tensor.desc.len // descriptor에 저장된 element count 반환.
    }

    pub fn is_empty(&self) -> bool {
        self.values().is_empty()
    }
}

#[cfg(test)]
mod tests {
    use super::ExsiaInput;
    use crate::{ExsiaConfig, ExsiaError, ExsiaPrecision, EXSIA_BLOCK_SIZE};
    use aqua_runtime::HostTensor;

    const fn config(block_size: usize) -> ExsiaConfig {
        ExsiaConfig {
            precision: ExsiaPrecision::I8,
            block_size,
        }
    }

    #[test]
    fn rejects_zero_block_size() {
        let tensor = HostTensor::f32(vec![1], vec![1.0]).expect("valid host tensor");
        let result = ExsiaInput::new(&tensor, config(0));

        assert!(matches!(
            result,
            Err(ExsiaError::InvalidBlockSize {
                block_size: 0,
                maximum: EXSIA_BLOCK_SIZE,
            })
        ));
    }

    #[test]
    fn rejects_block_size_above_canonical_maximum() {
        let tensor = HostTensor::f32(vec![1], vec![1.0]).expect("valid host tensor");
        let result = ExsiaInput::new(&tensor, config(EXSIA_BLOCK_SIZE + 1));

        assert!(matches!(
            result,
            Err(ExsiaError::InvalidBlockSize {
                block_size,
                maximum: EXSIA_BLOCK_SIZE,
            }) if block_size == EXSIA_BLOCK_SIZE + 1
        ));
    }
}
