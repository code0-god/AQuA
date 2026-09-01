use super::{AquaHardwareGeometry, LimitingResource, MatmulShape, TileFactors, TilingError};
use aqua_protocol::AQUA_BLOCK_SIZE;

#[derive(Clone, Copy)]
pub(super) struct ResourceUsage {
    pub(super) stripe_rows: usize,
    pub(super) n_tile_columns: usize,
    pub(super) k_tile_elements: usize,
    pub(super) activation_spad_rows: usize,
    pub(super) weight_spad_rows: usize,
    pub(super) hp1_metadata_bytes: usize,
    pub(super) accumulator_rows_per_bank: usize,
    pub(super) exsia_slot_bytes: usize,
}

pub(super) fn padded_to_dim(value: usize, dim: usize) -> Result<usize, TilingError> {
    let matrices = value / dim + usize::from(!value.is_multiple_of(dim));
    matrices
        .checked_mul(dim)
        .ok_or(TilingError::ArithmeticOverflow {
            calculation: "dimension padding",
        })
}

pub(super) fn resource_usage(
    geometry: AquaHardwareGeometry,
    shape: MatmulShape,
    factors: TileFactors,
) -> Result<ResourceUsage, TilingError> {
    let stripe_rows = factor_extent(factors.i(), geometry.array_dim(), shape.m())?;
    let n_tile_columns = factor_extent(factors.j(), geometry.array_dim(), shape.n())?;
    let k_tile_elements = factor_extent(factors.k(), geometry.array_dim(), shape.k())?;
    Ok(ResourceUsage {
        stripe_rows,
        n_tile_columns,
        k_tile_elements,
        activation_spad_rows: total_activation_spad_rows(factors, geometry)?,
        weight_spad_rows: total_weight_spad_rows(factors, geometry)?,
        hp1_metadata_bytes: hp1_metadata_bytes(n_tile_columns, k_tile_elements, geometry)?,
        accumulator_rows_per_bank: accumulator_rows_per_bank(factors, geometry)?,
        exsia_slot_bytes: exsia_slot_bytes(stripe_rows, shape.k(), geometry)?,
    })
}

pub(super) fn limiting_resource(
    geometry: AquaHardwareGeometry,
    usage: ResourceUsage,
) -> Option<LimitingResource> {
    if usage.activation_spad_rows > geometry.usable_activation_spad_rows() {
        Some(LimitingResource::ActivationSpad)
    } else if usage.weight_spad_rows > geometry.usable_weight_spad_rows() {
        Some(LimitingResource::WeightSpad)
    } else if usage.accumulator_rows_per_bank > geometry.usable_accumulator_rows_per_bank() {
        Some(LimitingResource::Accumulator)
    } else if usage.hp1_metadata_bytes > geometry.hp1_metadata_capacity_bytes() {
        Some(LimitingResource::Hp1Metadata)
    } else if usage.exsia_slot_bytes > geometry.exsia_slot_bytes() {
        Some(LimitingResource::ExsiaStripeSlot)
    } else {
        None
    }
}

fn total_activation_spad_rows(
    factors: TileFactors,
    geometry: AquaHardwareGeometry,
) -> Result<usize, TilingError> {
    checked_product(
        &[factors.i(), factors.k(), geometry.array_dim()],
        "activation scratchpad rows",
    )
}

fn total_weight_spad_rows(
    factors: TileFactors,
    geometry: AquaHardwareGeometry,
) -> Result<usize, TilingError> {
    checked_product(
        &[factors.k(), factors.j(), geometry.array_dim()],
        "weight scratchpad rows",
    )
}

fn accumulator_rows_per_bank(
    factors: TileFactors,
    geometry: AquaHardwareGeometry,
) -> Result<usize, TilingError> {
    checked_product(
        &[factors.i(), factors.j(), geometry.array_dim()],
        "accumulator rows",
    )
}

fn hp1_metadata_bytes(
    n_tile_columns: usize,
    k_tile_elements: usize,
    geometry: AquaHardwareGeometry,
) -> Result<usize, TilingError> {
    let blocks = k_tile_elements.div_ceil(AQUA_BLOCK_SIZE);
    let block_bits = checked_product(
        &[blocks, n_tile_columns, geometry.hp1_block_shift_bits()],
        "HP1 block metadata bits",
    )?;
    let row_bits = n_tile_columns
        .checked_mul(geometry.hp1_row_shift_bits())
        .ok_or(TilingError::ArithmeticOverflow {
            calculation: "HP1 row metadata bits",
        })?;
    bits_to_bytes(
        block_bits
            .checked_add(row_bits)
            .ok_or(TilingError::ArithmeticOverflow {
                calculation: "HP1 metadata bits",
            })?,
        "HP1 metadata bytes",
    )
}

fn exsia_slot_bytes(
    stripe_rows: usize,
    logical_k: usize,
    geometry: AquaHardwareGeometry,
) -> Result<usize, TilingError> {
    let layout = geometry.exsia_layout();
    let wide_bits = checked_product(
        &[stripe_rows, logical_k, layout.wide_value_bits()],
        "ExSIA wide-value bits",
    )?;
    let metadata_width = layout
        .exponent_bits()
        .checked_add(layout.outlier_mask_bits())
        .ok_or(TilingError::ArithmeticOverflow {
            calculation: "ExSIA metadata width",
        })?;
    let metadata_bits = checked_product(
        &[
            stripe_rows,
            logical_k.div_ceil(AQUA_BLOCK_SIZE),
            metadata_width,
        ],
        "ExSIA metadata bits",
    )?;
    bits_to_bytes(
        wide_bits
            .checked_add(metadata_bits)
            .ok_or(TilingError::ArithmeticOverflow {
                calculation: "ExSIA slot bits",
            })?,
        "ExSIA slot bytes",
    )
}

fn factor_extent(factor: usize, dim: usize, logical: usize) -> Result<usize, TilingError> {
    factor
        .checked_mul(dim)
        .map(|extent| extent.min(logical))
        .ok_or(TilingError::ArithmeticOverflow {
            calculation: "tile extent",
        })
}

fn checked_product(values: &[usize], calculation: &'static str) -> Result<usize, TilingError> {
    values.iter().try_fold(1_usize, |product, value| {
        product
            .checked_mul(*value)
            .ok_or(TilingError::ArithmeticOverflow { calculation })
    })
}

fn bits_to_bytes(bits: usize, calculation: &'static str) -> Result<usize, TilingError> {
    bits.checked_add(7)
        .map(|rounded| rounded / 8)
        .ok_or(TilingError::ArithmeticOverflow { calculation })
}
