use crate::{ExsiaConfig, ExsiaError};
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
}
