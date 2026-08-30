use crate::{
    ActivationExecutionPlan, ActivationMatrixShape, AquaHardwareGeometry, ExecutionPlanError,
    StripePlan,
};
use std::{error::Error, fmt};

mod capacity;
mod selector;

pub use selector::AquaTileSelector;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MatmulShape {
    m: usize,
    n: usize,
    k: usize,
}

impl MatmulShape {
    pub fn new(m: usize, n: usize, k: usize) -> Result<Self, TilingError> {
        for (dimension, value) in [("m", m), ("n", n), ("k", k)] {
            if value == 0 {
                return Err(TilingError::ZeroMatmulDimension { dimension });
            }
        }
        for (left, right, calculation) in [
            (m, k, "activation element count"),
            (k, n, "weight element count"),
            (m, n, "output element count"),
        ] {
            left.checked_mul(right)
                .ok_or(TilingError::ArithmeticOverflow { calculation })?;
        }
        Ok(Self { m, n, k })
    }

    pub const fn m(self) -> usize {
        self.m
    }

    pub const fn n(self) -> usize {
        self.n
    }

    pub const fn k(self) -> usize {
        self.k
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct TileFactors {
    i: usize,
    j: usize,
    k: usize,
}

impl TileFactors {
    pub(crate) const fn new(i: usize, j: usize, k: usize) -> Self {
        Self { i, j, k }
    }

    pub const fn i(self) -> usize {
        self.i
    }

    pub const fn j(self) -> usize {
        self.j
    }

    pub const fn k(self) -> usize {
        self.k
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct AquaTilePlan {
    geometry: AquaHardwareGeometry,
    shape: MatmulShape,
    factors: TileFactors,
    padded_m: usize,
    padded_n: usize,
    padded_k: usize,
    stripe_rows: usize,
    n_tile_columns: usize,
    k_tile_elements: usize,
    activation_spad_rows: usize,
    weight_spad_rows: usize,
    hp1_metadata_bytes: usize,
    accumulator_rows: usize,
    exsia_slot_bytes: usize,
}

impl AquaTilePlan {
    pub const fn geometry(self) -> AquaHardwareGeometry {
        self.geometry
    }

    pub const fn shape(self) -> MatmulShape {
        self.shape
    }

    pub const fn factors(self) -> TileFactors {
        self.factors
    }

    pub const fn padded_m(self) -> usize {
        self.padded_m
    }

    pub const fn padded_n(self) -> usize {
        self.padded_n
    }

    pub const fn padded_k(self) -> usize {
        self.padded_k
    }

    pub const fn stripe_rows(self) -> usize {
        self.stripe_rows
    }

    pub const fn n_tile_columns(self) -> usize {
        self.n_tile_columns
    }

    pub const fn k_tile_elements(self) -> usize {
        self.k_tile_elements
    }

    pub const fn activation_spad_rows(self) -> usize {
        self.activation_spad_rows
    }

    pub const fn weight_spad_rows(self) -> usize {
        self.weight_spad_rows
    }

    pub const fn hp1_metadata_bytes(self) -> usize {
        self.hp1_metadata_bytes
    }

    pub const fn accumulator_rows(self) -> usize {
        self.accumulator_rows
    }

    pub const fn exsia_slot_bytes(self) -> usize {
        self.exsia_slot_bytes
    }

    pub fn activation_plan(self) -> Result<ActivationExecutionPlan, ExecutionPlanError> {
        let matrix = ActivationMatrixShape::from_tensor_shape(&[self.shape.m, self.shape.k])?;
        let stripe_count = self.shape.m.div_ceil(self.stripe_rows);
        let mut stripes = Vec::with_capacity(stripe_count);
        let mut row_start = 0;
        while row_start < self.shape.m {
            let row_end = row_start
                .checked_add(self.stripe_rows)
                .ok_or(ExecutionPlanError::ElementCountOverflow)?
                .min(self.shape.m);
            stripes.push(StripePlan::new(stripes.len(), row_start, row_end));
            row_start = row_end;
        }
        ActivationExecutionPlan::new(matrix, stripes)
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum LimitingResource {
    ActivationSpad,
    WeightSpad,
    Hp1Metadata,
    Accumulator,
    ExsiaStripeSlot,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub enum TilingError {
    ZeroMatmulDimension {
        dimension: &'static str,
    },
    ArithmeticOverflow {
        calculation: &'static str,
    },
    NoFeasibleTile {
        shape: MatmulShape,
        limiting_resource: LimitingResource,
    },
}

impl fmt::Display for TilingError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ZeroMatmulDimension { dimension } => {
                write!(formatter, "matmul dimension {dimension} must be nonzero")
            }
            Self::ArithmeticOverflow { calculation } => {
                write!(formatter, "{calculation} overflow")
            }
            Self::NoFeasibleTile {
                shape,
                limiting_resource,
            } => write!(
                formatter,
                "no feasible tile for {shape:?}; limiting resource: {limiting_resource:?}"
            ),
        }
    }
}

impl Error for TilingError {}

#[cfg(test)]
mod tests;
