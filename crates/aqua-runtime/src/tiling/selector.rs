use super::capacity::{limiting_resource, padded_to_dim, resource_usage};
use super::{
    AquaHardwareGeometry, AquaTilePlan, LimitingResource, MatmulShape, TileFactors, TilingError,
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AquaTileSelector {
    geometry: AquaHardwareGeometry,
}

impl AquaTileSelector {
    pub const fn new(geometry: AquaHardwareGeometry) -> Self {
        Self { geometry }
    }

    pub fn select(self, shape: MatmulShape) -> Result<AquaTilePlan, TilingError> {
        let dim = self.geometry.array_dim();
        let padded_m = padded_to_dim(shape.m(), dim)?;
        let padded_n = padded_to_dim(shape.n(), dim)?;
        let padded_k = padded_to_dim(shape.k(), dim)?;
        let matrix_i = padded_m / dim;
        let matrix_j = padded_n / dim;
        let matrix_k = padded_k / dim;
        let accumulator_matrices = self.geometry.usable_accumulator_rows_per_bank() / dim;
        let max_i_j = integer_sqrt(accumulator_matrices);
        if max_i_j == 0 {
            return no_feasible(shape, LimitingResource::Accumulator);
        }
        let partition_matrices = self
            .geometry
            .usable_activation_spad_rows()
            .min(self.geometry.usable_weight_spad_rows())
            / dim;
        if partition_matrices == 0 {
            let resource = if self.geometry.usable_activation_spad_rows()
                < self.geometry.usable_weight_spad_rows()
            {
                LimitingResource::ActivationSpad
            } else {
                LimitingResource::WeightSpad
            };
            return no_feasible(shape, resource);
        }
        let max_k = (partition_matrices / max_i_j).max(1);
        let mut factors = TileFactors::new(
            matrix_i.min(max_i_j),
            matrix_j.min(max_i_j),
            matrix_k.min(max_k),
        );
        factors = reduce_to_feasible(self.geometry, shape, factors)?;
        factors = grow_factors(self.geometry, shape, factors, matrix_i, matrix_j, matrix_k)?;
        let usage = resource_usage(self.geometry, shape, factors)?;
        Ok(AquaTilePlan {
            geometry: self.geometry,
            shape,
            factors,
            padded_m,
            padded_n,
            padded_k,
            stripe_rows: usage.stripe_rows,
            n_tile_columns: usage.n_tile_columns,
            k_tile_elements: usage.k_tile_elements,
            activation_spad_rows: usage.activation_spad_rows,
            weight_spad_rows: usage.weight_spad_rows,
            hp1_block_metadata_entries: usage.hp1_block_metadata_entries,
            hp1_row_metadata_entries: usage.hp1_row_metadata_entries,
            hp1_metadata_bytes: usage.hp1_metadata_bytes,
            accumulator_rows_per_bank: usage.accumulator_rows_per_bank,
            exsia_slot_bytes: usage.exsia_slot_bytes,
        })
    }
}

fn reduce_to_feasible(
    geometry: AquaHardwareGeometry,
    shape: MatmulShape,
    mut factors: TileFactors,
) -> Result<TileFactors, TilingError> {
    loop {
        let usage = resource_usage(geometry, shape, factors)?;
        let Some(resource) = limiting_resource(geometry, usage) else {
            return Ok(factors);
        };
        factors = match resource {
            LimitingResource::ActivationSpad if factors.i() > 1 => {
                TileFactors::new(factors.i() - 1, factors.j(), factors.k())
            }
            LimitingResource::ActivationSpad if factors.k() > 1 => {
                TileFactors::new(factors.i(), factors.j(), factors.k() - 1)
            }
            LimitingResource::WeightSpad if factors.j() > 1 => {
                TileFactors::new(factors.i(), factors.j() - 1, factors.k())
            }
            LimitingResource::WeightSpad if factors.k() > 1 => {
                TileFactors::new(factors.i(), factors.j(), factors.k() - 1)
            }
            LimitingResource::Accumulator if factors.j() > 1 => {
                TileFactors::new(factors.i(), factors.j() - 1, factors.k())
            }
            LimitingResource::Accumulator if factors.i() > 1 => {
                TileFactors::new(factors.i() - 1, factors.j(), factors.k())
            }
            LimitingResource::Hp1Metadata if factors.k() > 1 => {
                TileFactors::new(factors.i(), factors.j(), factors.k() - 1)
            }
            LimitingResource::Hp1Metadata if factors.j() > 1 => {
                TileFactors::new(factors.i(), factors.j() - 1, factors.k())
            }
            LimitingResource::ExsiaStripeSlot if factors.i() > 1 => {
                TileFactors::new(factors.i() - 1, factors.j(), factors.k())
            }
            _ => return no_feasible(shape, resource),
        };
    }
}

fn grow_factors(
    geometry: AquaHardwareGeometry,
    shape: MatmulShape,
    mut factors: TileFactors,
    matrix_i: usize,
    matrix_j: usize,
    matrix_k: usize,
) -> Result<TileFactors, TilingError> {
    loop {
        let mut increased = false;
        if factors.j() < matrix_j {
            let candidate = TileFactors::new(factors.i(), factors.j() + 1, factors.k());
            if limiting_resource(geometry, resource_usage(geometry, shape, candidate)?).is_none() {
                factors = candidate;
                increased = true;
            }
        }
        if factors.i() < matrix_i {
            let candidate = TileFactors::new(factors.i() + 1, factors.j(), factors.k());
            if limiting_resource(geometry, resource_usage(geometry, shape, candidate)?).is_none() {
                factors = candidate;
                increased = true;
            }
        }
        if factors.k() < matrix_k {
            let candidate = TileFactors::new(factors.i(), factors.j(), factors.k() + 1);
            if limiting_resource(geometry, resource_usage(geometry, shape, candidate)?).is_none() {
                factors = candidate;
                increased = true;
            }
        }
        if !increased {
            return Ok(factors);
        }
    }
}

fn integer_sqrt(value: usize) -> usize {
    if value < 2 {
        return value;
    }
    let mut current = value;
    let mut next = value / 2 + value % 2;
    while next < current {
        current = next;
        next = (current + value / current) / 2;
    }
    current
}

fn no_feasible<T>(
    shape: MatmulShape,
    limiting_resource: LimitingResource,
) -> Result<T, TilingError> {
    Err(TilingError::NoFeasibleTile {
        shape,
        limiting_resource,
    })
}
