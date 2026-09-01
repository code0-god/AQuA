use std::{error::Error, fmt};

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum WeightError {
    RankTooSmall {
        rank: usize,
    },
    EmptyK,
    KNotBlockAligned {
        k: usize,
        block_size: usize,
    },
    ShapeElementCountOverflow,
    PayloadLengthOverflow,
    PayloadLengthMismatch {
        expected: usize,
        actual: usize,
    },
    NegativeBlockShift {
        row: usize,
        block: usize,
        value: i16,
    },
    InvalidZeroBlockEncoding {
        row: usize,
        block: usize,
    },
    NonzeroPadding {
        row: usize,
        block: usize,
        padding: [u8; 2],
    },
    InvalidCode {
        row: usize,
        block: usize,
        index: usize,
        value: i8,
    },
    InconsistentRowScale {
        row: usize,
        expected_bits: u32,
        actual_bits: u32,
    },
    InvalidRowScale {
        row: usize,
        bits: u32,
    },
    ZeroScaleWithNonzeroBlock {
        row: usize,
    },
    NonzeroScaleForZeroRow {
        row: usize,
    },
    InvalidEffectiveBlockScale {
        row: usize,
        block: usize,
        row_exponent: i16,
        shift: u16,
    },
    DuplicateTensorName {
        name: String,
    },
    StatisticsOverflow,
    UnsupportedQ8H1,
}

impl fmt::Display for WeightError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::RankTooSmall { rank } => {
                write!(
                    formatter,
                    "matrix weight rank must be at least 2, got {rank}"
                )
            }
            Self::EmptyK => formatter.write_str("matrix weight K must be nonzero"),
            Self::KNotBlockAligned { k, block_size } => write!(
                formatter,
                "matrix weight K {k} is not divisible by block size {block_size}"
            ),
            Self::ShapeElementCountOverflow => {
                formatter.write_str("matrix weight shape element count overflow")
            }
            Self::PayloadLengthOverflow => {
                formatter.write_str("HP1 payload length calculation overflow")
            }
            Self::PayloadLengthMismatch { expected, actual } => write!(
                formatter,
                "HP1 payload length mismatch: expected {expected}, got {actual}"
            ),
            Self::NegativeBlockShift { row, block, value } => write!(
                formatter,
                "HP1 row {row} block {block} has negative non-sentinel shift {value}"
            ),
            Self::InvalidZeroBlockEncoding { row, block } => write!(
                formatter,
                "invalid HP1 zero-block encoding at row {row} block {block}"
            ),
            Self::NonzeroPadding {
                row,
                block,
                padding,
            } => write!(
                formatter,
                "HP1 row {row} block {block} has nonzero padding {padding:?}"
            ),
            Self::InvalidCode {
                row,
                block,
                index,
                value,
            } => write!(
                formatter,
                "HP1 row {row} block {block} code {index} has invalid value {value}"
            ),
            Self::InconsistentRowScale {
                row,
                expected_bits,
                actual_bits,
            } => write!(
                formatter,
                "inconsistent HP1 row channel scale at row {row}: \
                 expected 0x{expected_bits:08x}, got 0x{actual_bits:08x}"
            ),
            Self::InvalidRowScale { row, bits } => write!(
                formatter,
                "invalid HP1 row channel scale at row {row}: 0x{bits:08x}"
            ),
            Self::ZeroScaleWithNonzeroBlock { row } => {
                write!(
                    formatter,
                    "HP1 zero-scale row {row} contains a nonzero block"
                )
            }
            Self::NonzeroScaleForZeroRow { row } => {
                write!(
                    formatter,
                    "HP1 all-zero row {row} has a nonzero channel scale"
                )
            }
            Self::InvalidEffectiveBlockScale {
                row,
                block,
                row_exponent,
                shift,
            } => write!(
                formatter,
                "HP1 row {row} block {block} effective scale exponent is invalid: \
                 row exponent {row_exponent}, shift {shift}"
            ),
            Self::DuplicateTensorName { name } => {
                write!(formatter, "duplicate HP1 tensor name '{name}'")
            }
            Self::StatisticsOverflow => formatter.write_str("HP1 statistics count overflow"),
            Self::UnsupportedQ8H1 => {
                formatter.write_str("Q8_H1 canonical weight extraction is not supported")
            }
        }
    }
}

impl Error for WeightError {}
