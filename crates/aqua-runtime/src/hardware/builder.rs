use super::{AquaHardwareGeometry, ExsiaSlotLayout, HardwareGeometryError};
use aqua_protocol::AQUA_BLOCK_SIZE;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AquaHardwareGeometryBuilder {
    geometry: AquaHardwareGeometry,
}

impl AquaHardwareGeometryBuilder {
    pub(super) const fn new(array_dim: usize) -> Self {
        Self {
            geometry: AquaHardwareGeometry {
                array_dim,
                activation_spad_banks: 0,
                activation_spad_rows_per_bank: 0,
                weight_spad_banks: 0,
                weight_spad_rows_per_bank: 0,
                accumulator_banks: 0,
                accumulator_rows_per_bank: 0,
                exsia_slot_count: 0,
                exsia_slot_bytes: 0,
                hp1_metadata_capacity_bytes: 0,
                activation_element_bits: 0,
                weight_element_bits: 0,
                accumulator_element_bits: 0,
                hp1_block_shift_bits: 0,
                hp1_row_shift_bits: 0,
                exsia_layout: ExsiaSlotLayout {
                    wide_value_bits: 0,
                    exponent_bits: 0,
                    outlier_mask_bits: 0,
                },
                double_buffer_activation: false,
                double_buffer_weight: false,
                double_buffer_accumulator: false,
            },
        }
    }

    pub const fn activation_spad(mut self, banks: usize, rows_per_bank: usize) -> Self {
        self.geometry.activation_spad_banks = banks;
        self.geometry.activation_spad_rows_per_bank = rows_per_bank;
        self
    }

    pub const fn weight_spad(mut self, banks: usize, rows_per_bank: usize) -> Self {
        self.geometry.weight_spad_banks = banks;
        self.geometry.weight_spad_rows_per_bank = rows_per_bank;
        self
    }

    pub const fn accumulator(mut self, banks: usize, rows_per_bank: usize) -> Self {
        self.geometry.accumulator_banks = banks;
        self.geometry.accumulator_rows_per_bank = rows_per_bank;
        self
    }

    pub const fn exsia_slots(mut self, count: usize, bytes_per_slot: usize) -> Self {
        self.geometry.exsia_slot_count = count;
        self.geometry.exsia_slot_bytes = bytes_per_slot;
        self
    }

    pub const fn element_bits(
        mut self,
        activation: usize,
        weight: usize,
        accumulator: usize,
    ) -> Self {
        self.geometry.activation_element_bits = activation;
        self.geometry.weight_element_bits = weight;
        self.geometry.accumulator_element_bits = accumulator;
        self
    }

    pub const fn hp1_metadata(
        mut self,
        capacity_bytes: usize,
        block_shift_bits: usize,
        row_shift_bits: usize,
    ) -> Self {
        self.geometry.hp1_metadata_capacity_bytes = capacity_bytes;
        self.geometry.hp1_block_shift_bits = block_shift_bits;
        self.geometry.hp1_row_shift_bits = row_shift_bits;
        self
    }

    pub const fn exsia_layout(
        mut self,
        wide_value_bits: usize,
        exponent_bits: usize,
        outlier_mask_bits: usize,
    ) -> Self {
        self.geometry.exsia_layout = ExsiaSlotLayout {
            wide_value_bits,
            exponent_bits,
            outlier_mask_bits,
        };
        self
    }

    pub const fn double_buffering(
        mut self,
        activation: bool,
        weight: bool,
        accumulator: bool,
    ) -> Self {
        self.geometry.double_buffer_activation = activation;
        self.geometry.double_buffer_weight = weight;
        self.geometry.double_buffer_accumulator = accumulator;
        self
    }

    pub fn build(self) -> Result<AquaHardwareGeometry, HardwareGeometryError> {
        validate_nonzero(self.geometry)?;
        validate_array_dim(self.geometry)?;
        validate_capacities(self.geometry)?;
        Ok(self.geometry)
    }
}

fn validate_nonzero(geometry: AquaHardwareGeometry) -> Result<(), HardwareGeometryError> {
    for (field, value) in [
        ("array_dim", geometry.array_dim),
        ("activation_spad_banks", geometry.activation_spad_banks),
        (
            "activation_spad_rows_per_bank",
            geometry.activation_spad_rows_per_bank,
        ),
        ("weight_spad_banks", geometry.weight_spad_banks),
        (
            "weight_spad_rows_per_bank",
            geometry.weight_spad_rows_per_bank,
        ),
        ("accumulator_banks", geometry.accumulator_banks),
        (
            "accumulator_rows_per_bank",
            geometry.accumulator_rows_per_bank,
        ),
        ("exsia_slot_count", geometry.exsia_slot_count),
        ("exsia_slot_bytes", geometry.exsia_slot_bytes),
        (
            "hp1_metadata_capacity_bytes",
            geometry.hp1_metadata_capacity_bytes,
        ),
        ("activation_element_bits", geometry.activation_element_bits),
        ("weight_element_bits", geometry.weight_element_bits),
        (
            "accumulator_element_bits",
            geometry.accumulator_element_bits,
        ),
        ("hp1_block_shift_bits", geometry.hp1_block_shift_bits),
        ("hp1_row_shift_bits", geometry.hp1_row_shift_bits),
        (
            "exsia_wide_value_bits",
            geometry.exsia_layout.wide_value_bits,
        ),
        ("exsia_exponent_bits", geometry.exsia_layout.exponent_bits),
        (
            "exsia_outlier_mask_bits",
            geometry.exsia_layout.outlier_mask_bits,
        ),
    ] {
        if value == 0 {
            return Err(HardwareGeometryError::ZeroField { field });
        }
    }
    Ok(())
}

fn validate_array_dim(geometry: AquaHardwareGeometry) -> Result<(), HardwareGeometryError> {
    if !geometry.array_dim.is_multiple_of(AQUA_BLOCK_SIZE)
        && !AQUA_BLOCK_SIZE.is_multiple_of(geometry.array_dim)
    {
        return Err(HardwareGeometryError::IncompatibleArrayDim {
            array_dim: geometry.array_dim,
            block_size: AQUA_BLOCK_SIZE,
        });
    }
    if !matches!(geometry.array_dim, 16 | 32 | 64) {
        return Err(HardwareGeometryError::UnsupportedArrayDim {
            array_dim: geometry.array_dim,
        });
    }
    if geometry.accumulator_banks != geometry.array_dim {
        return Err(HardwareGeometryError::IncompatibleAccumulatorBanks {
            array_dim: geometry.array_dim,
            banks: geometry.accumulator_banks,
        });
    }
    Ok(())
}

fn validate_capacities(geometry: AquaHardwareGeometry) -> Result<(), HardwareGeometryError> {
    for (resource, banks, rows, bits) in [
        (
            "activation_spad",
            geometry.activation_spad_banks,
            geometry.activation_spad_rows_per_bank,
            geometry.activation_element_bits,
        ),
        (
            "weight_spad",
            geometry.weight_spad_banks,
            geometry.weight_spad_rows_per_bank,
            geometry.weight_element_bits,
        ),
        (
            "accumulator",
            geometry.accumulator_banks,
            geometry.accumulator_rows_per_bank,
            geometry.accumulator_element_bits,
        ),
    ] {
        let total_rows = banks
            .checked_mul(rows)
            .ok_or(HardwareGeometryError::CapacityOverflow { resource })?;
        total_rows
            .checked_mul(geometry.array_dim)
            .and_then(|elements| elements.checked_mul(bits))
            .ok_or(HardwareGeometryError::CapacityOverflow { resource })?;
    }
    geometry
        .exsia_slot_count
        .checked_mul(geometry.exsia_slot_bytes)
        .ok_or(HardwareGeometryError::CapacityOverflow {
            resource: "exsia_slots",
        })?;
    for (resource, usable_rows) in [
        ("activation_spad", geometry.usable_activation_spad_rows()),
        ("weight_spad", geometry.usable_weight_spad_rows()),
        ("accumulator", geometry.usable_accumulator_rows_per_bank()),
    ] {
        if usable_rows == 0 {
            return Err(HardwareGeometryError::EmptyUsableCapacity { resource });
        }
    }
    Ok(())
}
