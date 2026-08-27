/// Canonical ExSIA activation block size used bt AQuA.
pub const EXSIA_BLOCK_SIZE: usize = 32;

/// Integer precision produced by ExSIA.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum ExsiaPrecision {
    I4,
    I8,
    I16,
}

impl ExsiaPrecision {
    pub const fn bits(self) -> u8 {
        match self {
            Self::I4 => 4,
            Self::I8 => 8,
            Self::I16 => 16,
        }
    }
}

/// ExSIA execution configuration.
///
/// Keep this deliberately small untill the canonical software implementation
/// has been fully traced.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ExsiaConfig {
    pub precision: ExsiaPrecision,
    pub block_size: usize,
}

impl ExsiaConfig {
    pub const fn new(precision: ExsiaPrecision) -> Self {
        Self {
            precision,
            block_size: EXSIA_BLOCK_SIZE,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::{ExsiaConfig, ExsiaPrecision, EXSIA_BLOCK_SIZE};

    #[test]
    fn uses_canonical_block_size() {
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        assert_eq!(config.block_size, EXSIA_BLOCK_SIZE);
        assert_eq!(config.block_size, 32);
    }

    #[test]
    fn reports_precision_bits() {
        assert_eq!(ExsiaPrecision::I4.bits(), 4);
        assert_eq!(ExsiaPrecision::I8.bits(), 8);
        assert_eq!(ExsiaPrecision::I16.bits(), 16);
    }
}
