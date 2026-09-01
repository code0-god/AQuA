use std::{error::Error, fmt};

mod builder;

pub use builder::AquaHardwareGeometryBuilder;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ExsiaSlotLayout {
    wide_value_bits: usize,
    exponent_bits: usize,
    outlier_mask_bits: usize,
}

impl ExsiaSlotLayout {
    pub const fn wide_value_bits(self) -> usize {
        self.wide_value_bits
    }

    pub const fn exponent_bits(self) -> usize {
        self.exponent_bits
    }

    pub const fn outlier_mask_bits(self) -> usize {
        self.outlier_mask_bits
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Hp1MetaGeometry {
    /// Number of array-wide block-scale vectors resident in hardware.
    pub block_entries: usize,
    /// Number of array-wide row-shift vectors resident in hardware.
    pub row_entries: usize,
    /// Bit width of `leftShift`; encoded block scales use one extra `zeroBlock` bit.
    pub left_shift_bits: usize,
    /// Bit width of the row-level right-shift magnitude.
    pub row_right_shift_bits: usize,
}

impl Hp1MetaGeometry {
    fn capacity_bytes(self, array_dim: usize) -> Result<usize, HardwareGeometryError> {
        let overflow = HardwareGeometryError::CapacityOverflow {
            resource: "hp1_metadata",
        };
        let block_scale_bits = self
            .left_shift_bits
            .checked_add(1)
            .ok_or_else(|| overflow.clone())?;
        let block_bits = self
            .block_entries
            .checked_mul(array_dim)
            .and_then(|entries| entries.checked_mul(block_scale_bits))
            .ok_or_else(|| overflow.clone())?;
        let row_bits = self
            .row_entries
            .checked_mul(array_dim)
            .and_then(|entries| entries.checked_mul(self.row_right_shift_bits))
            .ok_or_else(|| overflow.clone())?;
        block_bits
            .checked_add(row_bits)
            .and_then(|bits| bits.checked_add(7))
            .map(|bits| bits / 8)
            .ok_or(overflow)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AquaHardwareGeometry {
    array_dim: usize,
    activation_spad_banks: usize,
    activation_spad_rows_per_bank: usize,
    weight_spad_banks: usize,
    weight_spad_rows_per_bank: usize,
    accumulator_banks: usize,
    accumulator_rows_per_bank: usize,
    exsia_slot_count: usize,
    exsia_slot_bytes: usize,
    hp1_metadata_capacity_bytes: usize,
    activation_element_bits: usize,
    weight_element_bits: usize,
    accumulator_element_bits: usize,
    hp1_meta: Hp1MetaGeometry,
    exsia_layout: ExsiaSlotLayout,
    double_buffer_activation: bool,
    double_buffer_weight: bool,
    double_buffer_accumulator: bool,
}

impl AquaHardwareGeometry {
    pub const fn builder(array_dim: usize) -> AquaHardwareGeometryBuilder {
        AquaHardwareGeometryBuilder::new(array_dim)
    }

    pub const fn array_dim(self) -> usize {
        self.array_dim
    }

    pub const fn activation_spad_banks(self) -> usize {
        self.activation_spad_banks
    }

    pub const fn activation_spad_rows_per_bank(self) -> usize {
        self.activation_spad_rows_per_bank
    }

    pub const fn weight_spad_banks(self) -> usize {
        self.weight_spad_banks
    }

    pub const fn weight_spad_rows_per_bank(self) -> usize {
        self.weight_spad_rows_per_bank
    }

    pub const fn accumulator_banks(self) -> usize {
        self.accumulator_banks
    }

    pub const fn accumulator_rows_per_bank(self) -> usize {
        self.accumulator_rows_per_bank
    }

    pub const fn exsia_slot_count(self) -> usize {
        self.exsia_slot_count
    }

    pub const fn exsia_slot_bytes(self) -> usize {
        self.exsia_slot_bytes
    }

    pub const fn hp1_metadata_capacity_bytes(self) -> usize {
        self.hp1_metadata_capacity_bytes
    }

    pub const fn activation_element_bits(self) -> usize {
        self.activation_element_bits
    }

    pub const fn weight_element_bits(self) -> usize {
        self.weight_element_bits
    }

    pub const fn accumulator_element_bits(self) -> usize {
        self.accumulator_element_bits
    }

    pub const fn hp1_block_metadata_entries(self) -> usize {
        self.hp1_meta.block_entries
    }

    pub const fn hp1_row_metadata_entries(self) -> usize {
        self.hp1_meta.row_entries
    }

    pub const fn hp1_left_shift_bits(self) -> usize {
        self.hp1_meta.left_shift_bits
    }

    pub const fn hp1_row_right_shift_bits(self) -> usize {
        self.hp1_meta.row_right_shift_bits
    }

    pub const fn hp1_meta_geometry(self) -> Hp1MetaGeometry {
        self.hp1_meta
    }

    pub const fn exsia_layout(self) -> ExsiaSlotLayout {
        self.exsia_layout
    }

    pub const fn double_buffer_activation(self) -> bool {
        self.double_buffer_activation
    }

    pub const fn double_buffer_weight(self) -> bool {
        self.double_buffer_weight
    }

    pub const fn double_buffer_accumulator(self) -> bool {
        self.double_buffer_accumulator
    }

    pub const fn activation_spad_rows(self) -> usize {
        self.activation_spad_banks * self.activation_spad_rows_per_bank
    }

    pub const fn weight_spad_rows(self) -> usize {
        self.weight_spad_banks * self.weight_spad_rows_per_bank
    }

    pub const fn accumulator_rows(self) -> usize {
        self.accumulator_banks * self.accumulator_rows_per_bank
    }

    pub const fn usable_activation_spad_rows(self) -> usize {
        usable_rows(self.activation_spad_rows(), self.double_buffer_activation)
    }

    pub const fn usable_weight_spad_rows(self) -> usize {
        usable_rows(self.weight_spad_rows(), self.double_buffer_weight)
    }

    pub const fn usable_accumulator_rows_per_bank(self) -> usize {
        usable_rows(
            self.accumulator_rows_per_bank,
            self.double_buffer_accumulator,
        )
    }
}

const fn usable_rows(rows: usize, double_buffered: bool) -> usize {
    if double_buffered {
        rows / 2
    } else {
        rows
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum HardwareGeometryError {
    ZeroField { field: &'static str },
    IncompatibleArrayDim { array_dim: usize, block_size: usize },
    UnsupportedArrayDim { array_dim: usize },
    IncompatibleAccumulatorBanks { array_dim: usize, banks: usize },
    CapacityOverflow { resource: &'static str },
    EmptyUsableCapacity { resource: &'static str },
}

impl fmt::Display for HardwareGeometryError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ZeroField { field } => write!(formatter, "{field} must be nonzero"),
            Self::IncompatibleArrayDim {
                array_dim,
                block_size,
            } => write!(
                formatter,
                "array dimension {array_dim} and block size {block_size} must divide one another"
            ),
            Self::UnsupportedArrayDim { array_dim } => {
                write!(formatter, "array dimension {array_dim} is not supported")
            }
            Self::IncompatibleAccumulatorBanks { array_dim, banks } => write!(
                formatter,
                "accumulator banks {banks} must equal array dimension {array_dim}"
            ),
            Self::CapacityOverflow { resource } => {
                write!(formatter, "{resource} capacity calculation overflow")
            }
            Self::EmptyUsableCapacity { resource } => {
                write!(formatter, "{resource} has zero usable buffered capacity")
            }
        }
    }
}

impl Error for HardwareGeometryError {}

#[cfg(test)]
mod tests;
