use aqua_exsia::ExsiaPrecision;
use std::{error::Error, fmt};

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum RacoError {
    ResidualOutOfRange {
        value: i32,
        minimum: i32,
        maximum: i32,
    },
    ResidualNotRepresentable {
        value: i32,
        precision: ExsiaPrecision,
    },
    ZeroResidual {
        local_row: usize,
        k: usize,
    },
    DuplicateResidualCoordinate {
        local_row: usize,
        k: usize,
    },
    ResidualRowOutOfBounds {
        local_row: usize,
        row_count: usize,
    },
    ResidualKOutOfBounds {
        k: usize,
        logical_k: usize,
    },
    IndexDoesNotFitU32 {
        field: &'static str,
        value: usize,
    },
    InvalidCompactK {
        block_index: u32,
        value: u8,
    },
    InvalidLaneId {
        precision: ExsiaPrecision,
        lane_id: u8,
    },
    InvalidDigit {
        precision: ExsiaPrecision,
        value: i32,
    },
    LaneCapacityMismatch {
        precision: ExsiaPrecision,
        expected: u8,
        actual: u8,
    },
    DigitCompositionOverflow {
        precision: ExsiaPrecision,
    },
    InvalidDigitPayloadLength {
        expected: usize,
        actual: usize,
    },
    InvalidLogicalDimension {
        field: &'static str,
        value: usize,
    },
    ElementCountOverflow {
        field: &'static str,
    },
    WeightElementCountMismatch {
        expected: usize,
        actual: usize,
    },
    WeightKDoesNotMatch {
        residual_k: usize,
        weight_k: usize,
    },
    IndexOutOfBounds {
        field: &'static str,
        index: usize,
        len: usize,
    },
    DotProductOverflow {
        block_index: u32,
        lane_id: u8,
        local_row: usize,
        j: usize,
    },
    CompositionOverflow {
        block_index: u32,
        local_row: usize,
        j: usize,
    },
    CorrectionOverflow {
        local_row: usize,
        j: usize,
    },
    WorkOutputMismatch {
        reason: &'static str,
    },
}

impl fmt::Display for RacoError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ResidualOutOfRange {
                value,
                minimum,
                maximum,
            } => write!(
                formatter,
                "residual {value} is outside signed RaCo range {minimum}..={maximum}"
            ),
            Self::ResidualNotRepresentable { value, precision } => {
                write!(
                    formatter,
                    "residual {value} is not representable by {precision:?} RaCo lanes"
                )
            }
            Self::ZeroResidual { local_row, k } => {
                write!(formatter, "zero residual at local row {local_row}, K {k}")
            }
            Self::DuplicateResidualCoordinate { local_row, k } => write!(
                formatter,
                "duplicate residual coordinate at local row {local_row}, K {k}"
            ),
            Self::ResidualRowOutOfBounds {
                local_row,
                row_count,
            } => write!(
                formatter,
                "residual local row {local_row} exceeds row count {row_count}"
            ),
            Self::ResidualKOutOfBounds { k, logical_k } => {
                write!(formatter, "residual K {k} exceeds logical K {logical_k}")
            }
            Self::IndexDoesNotFitU32 { field, value } => {
                write!(formatter, "{field} value {value} does not fit u32")
            }
            Self::InvalidCompactK { block_index, value } => write!(
                formatter,
                "block {block_index} compact K value {value} is outside 0..31"
            ),
            Self::InvalidLaneId { precision, lane_id } => {
                write!(formatter, "lane {lane_id} is invalid for {precision:?}")
            }
            Self::InvalidDigit { precision, value } => {
                write!(formatter, "digit {value} is invalid for {precision:?}")
            }
            Self::LaneCapacityMismatch {
                precision,
                expected,
                actual,
            } => write!(
                formatter,
                "{precision:?} lane capacity mismatch: expected {expected}, got {actual}"
            ),
            Self::DigitCompositionOverflow { precision } => {
                write!(formatter, "{precision:?} digit composition exceeds i64")
            }
            Self::InvalidDigitPayloadLength { expected, actual } => write!(
                formatter,
                "digit payload length mismatch: expected {expected}, got {actual}"
            ),
            Self::InvalidLogicalDimension { field, value } => {
                write!(formatter, "invalid logical {field} dimension {value}")
            }
            Self::ElementCountOverflow { field } => {
                write!(formatter, "{field} element count overflow")
            }
            Self::WeightElementCountMismatch { expected, actual } => write!(
                formatter,
                "weight element count mismatch: expected {expected}, got {actual}"
            ),
            Self::WeightKDoesNotMatch {
                residual_k,
                weight_k,
            } => write!(
                formatter,
                "residual logical K {residual_k} does not match weight K {weight_k}"
            ),
            Self::IndexOutOfBounds { field, index, len } => {
                write!(formatter, "{field} index {index} exceeds length {len}")
            }
            Self::DotProductOverflow {
                block_index,
                lane_id,
                local_row,
                j,
            } => write!(
                formatter,
                "dot product overflow at block {block_index}, lane {lane_id}, row {local_row}, J {j}"
            ),
            Self::CompositionOverflow {
                block_index,
                local_row,
                j,
            } => write!(
                formatter,
                "radix composition overflow at block {block_index}, row {local_row}, J {j}"
            ),
            Self::CorrectionOverflow { local_row, j } => {
                write!(formatter, "correction overflow at row {local_row}, J {j}")
            }
            Self::WorkOutputMismatch { reason } => {
                write!(formatter, "RaCo work/output mismatch: {reason}")
            }
        }
    }
}

impl Error for RacoError {}
