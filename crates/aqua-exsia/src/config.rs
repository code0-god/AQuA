/// Canonical ExSIA activation block size used by AQuA.
pub const EXSIA_BLOCK_SIZE: usize = 32;

/// Canonical ExSIA sigma threshold used by AQuA.
pub const EXSIA_SIGMA: i32 = 2;

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

    pub const fn rho(self) -> i16 {
        // Signed N-bit quantization의 최대 magnitude가
        // 대략 2^(N-1)에 맞도록 exponent offset을 설정.
        //
        // I4  -> rho = 2
        // I8  -> rho = 6
        // I16 -> rho = 14
        self.bits() as i16 - 2
    }

    pub const fn qmin(self) -> i32 {
        match self {
            Self::I4 => -8,
            Self::I8 => -128,
            Self::I16 => -32_768,
        }
    }

    pub const fn qmax(self) -> i32 {
        match self {
            Self::I4 => 7,
            Self::I8 => 127,
            Self::I16 => 32_767,
        }
    }
}

/// ExSIA execution configuration.
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

    pub const fn rho(self) -> i16 {
        self.precision.rho()
    }

    pub const fn sigma(self) -> i32 {
        EXSIA_SIGMA
    }

    pub const fn qmin(self) -> i32 {
        self.precision.qmin()
    }

    pub const fn qmax(self) -> i32 {
        self.precision.qmax()
    }
}

#[cfg(test)]
mod tests {
    use super::{ExsiaConfig, ExsiaPrecision, EXSIA_BLOCK_SIZE, EXSIA_SIGMA};

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

    #[test]
    fn reports_precision_rho() {
        assert_eq!(ExsiaPrecision::I4.rho(), 2);
        assert_eq!(ExsiaPrecision::I8.rho(), 6);
        assert_eq!(ExsiaPrecision::I16.rho(), 14);
    }

    #[test]
    fn uses_canonical_sigma() {
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        assert_eq!(config.sigma(), EXSIA_SIGMA);
        assert_eq!(config.sigma(), 2);
    }

    #[test]
    fn reports_signed_quantization_range() {
        assert_eq!(ExsiaPrecision::I4.qmin(), -8);
        assert_eq!(ExsiaPrecision::I4.qmax(), 7);

        assert_eq!(ExsiaPrecision::I8.qmin(), -128);
        assert_eq!(ExsiaPrecision::I8.qmax(), 127);

        assert_eq!(ExsiaPrecision::I16.qmin(), -32_768);
        assert_eq!(ExsiaPrecision::I16.qmax(), 32_767);
    }
}
