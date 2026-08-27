use crate::{ExsiaError, ExsiaInput};

/// Canonical software ExSIA reference.
///
/// The implementation intentionally remains unavailable until the exact
/// ExSIA path used for model-quality evaluation has been identified and
/// frozen.
#[derive(Clone, Copy, Debug, Default)]
pub struct ReferenceExsia;

impl ReferenceExsia {
    pub const fn new() -> Self {
        Self
    }

    pub fn execute(&self, _input: &ExsiaInput<'_>) -> Result<(), ExsiaError> {
        Err(ExsiaError::ReferenceNotImplemented)
    }
}

#[cfg(test)]
mod tests {
    use super::ReferenceExsia;
    use crate::{ExsiaConfig, ExsiaError, ExsiaInput, ExsiaPrecision};
    use aqua_runtime::HostTensor;

    #[test]
    fn does_not_fake_reference_quantization() {
        let tensor = HostTensor::f32(vec![32], vec![0.0; 32]).expect("valid host tensor");

        let input = ExsiaInput::new(&tensor, ExsiaConfig::new(ExsiaPrecision::I8))
            .expect("valid ExSIA input");

        assert!(matches!(
            ReferenceExsia::new().execute(&input),
            Err(ExsiaError::ReferenceNotImplemented)
        ));
    }
}
