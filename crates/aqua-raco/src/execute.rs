use crate::{
    radix_contract, RacoBlockOutput, RacoCompressedOutput, RacoError, RacoStripeWork,
    RACO_MAX_LANES,
};
use aqua_protocol::AQUA_BLOCK_SIZE;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DenseWeightCodes<'a> {
    values: &'a [i32],
    logical_k: usize,
    logical_j: usize,
}

impl<'a> DenseWeightCodes<'a> {
    pub fn new(values: &'a [i32], logical_k: usize, logical_j: usize) -> Result<Self, RacoError> {
        if logical_k == 0 {
            return Err(RacoError::InvalidLogicalDimension {
                field: "K",
                value: 0,
            });
        }
        if logical_j == 0 {
            return Err(RacoError::InvalidLogicalDimension {
                field: "J",
                value: 0,
            });
        }
        let expected = logical_k
            .checked_mul(logical_j)
            .ok_or(RacoError::ElementCountOverflow {
                field: "weight codes",
            })?;
        if values.len() != expected {
            return Err(RacoError::WeightElementCountMismatch {
                expected,
                actual: values.len(),
            });
        }
        Ok(Self {
            values,
            logical_k,
            logical_j,
        })
    }

    pub const fn values(&self) -> &'a [i32] {
        self.values
    }

    pub const fn logical_k(&self) -> usize {
        self.logical_k
    }

    pub const fn logical_j(&self) -> usize {
        self.logical_j
    }

    pub(crate) fn value(&self, k: usize, j: usize) -> Result<i32, RacoError> {
        let index = k
            .checked_mul(self.logical_j)
            .and_then(|value| value.checked_add(j))
            .ok_or(RacoError::ElementCountOverflow {
                field: "weight code index",
            })?;
        self.values
            .get(index)
            .copied()
            .ok_or(RacoError::IndexOutOfBounds {
                field: "weight code",
                index,
                len: self.values.len(),
            })
    }
}

#[derive(Clone, Copy)]
struct DotCoordinate {
    block_index: u32,
    lane_id: u8,
    local_row: usize,
    j: usize,
}

pub fn execute_integer_reference(
    work: &RacoStripeWork,
    weights: &DenseWeightCodes<'_>,
) -> Result<RacoCompressedOutput, RacoError> {
    let residual_k =
        usize::try_from(work.logical_k()).map_err(|_| RacoError::WorkOutputMismatch {
            reason: "logical K does not fit usize",
        })?;
    if residual_k != weights.logical_k() {
        return Err(RacoError::WeightKDoesNotMatch {
            residual_k,
            weight_k: weights.logical_k(),
        });
    }
    let rows = usize::try_from(work.row_count()).map_err(|_| RacoError::WorkOutputMismatch {
        reason: "row count does not fit usize",
    })?;
    let logical_j_u32 =
        u32::try_from(weights.logical_j()).map_err(|_| RacoError::IndexDoesNotFitU32 {
            field: "logical J",
            value: weights.logical_j(),
        })?;
    let lane_capacity = radix_contract(work.precision()).lane_capacity();
    let mut output_blocks = Vec::with_capacity(work.blocks().len());

    for block in work.blocks() {
        if block.row_count() != work.row_count() {
            return Err(RacoError::WorkOutputMismatch {
                reason: "block row count differs from stripe work",
            });
        }
        let active_lanes = block.active_lane_ids();
        let output_len = active_lanes
            .len()
            .checked_mul(rows)
            .and_then(|len| len.checked_mul(weights.logical_j()))
            .ok_or(RacoError::ElementCountOverflow {
                field: "block output",
            })?;
        let mut values = Vec::with_capacity(output_len);

        for (lane_position, &lane_id) in active_lanes.iter().enumerate() {
            if lane_id >= lane_capacity {
                return Err(RacoError::InvalidLaneId {
                    precision: work.precision(),
                    lane_id,
                });
            }
            for local_row in 0..rows {
                for j in 0..weights.logical_j() {
                    let mut accumulator = 0_i128;
                    for (compact_position, &local_k) in block.compact_k().iter().enumerate() {
                        if usize::from(local_k) >= AQUA_BLOCK_SIZE {
                            return Err(RacoError::InvalidCompactK {
                                block_index: block.block_index(),
                                value: local_k,
                            });
                        }
                        let block_base = usize::try_from(block.block_index())
                            .map_err(|_| RacoError::WorkOutputMismatch {
                                reason: "block index does not fit usize",
                            })?
                            .checked_mul(AQUA_BLOCK_SIZE)
                            .ok_or(RacoError::ElementCountOverflow { field: "global K" })?;
                        let global_k = block_base
                            .checked_add(usize::from(local_k))
                            .ok_or(RacoError::ElementCountOverflow { field: "global K" })?;
                        if global_k >= weights.logical_k() {
                            return Err(RacoError::ResidualKOutOfBounds {
                                k: global_k,
                                logical_k: weights.logical_k(),
                            });
                        }
                        let digit = block.digit(lane_position, local_row, compact_position)?;
                        let weight = weights.value(global_k, j)?;
                        accumulator += i128::from(digit) * i128::from(weight);
                    }
                    values.push(checked_dot_output(
                        accumulator,
                        DotCoordinate {
                            block_index: block.block_index(),
                            lane_id,
                            local_row,
                            j,
                        },
                    )?);
                }
            }
        }

        let mut active_lane_ids = [0_u8; RACO_MAX_LANES];
        active_lane_ids[..active_lanes.len()].copy_from_slice(active_lanes);
        output_blocks.push(RacoBlockOutput {
            block_index: block.block_index(),
            active_lane_ids,
            active_lane_count: u8::try_from(active_lanes.len()).map_err(|_| {
                RacoError::ElementCountOverflow {
                    field: "active lane count",
                }
            })?,
            row_count: work.row_count(),
            logical_j: logical_j_u32,
            values,
        });
    }

    Ok(RacoCompressedOutput {
        stripe_index: work.stripe_index(),
        row_start: work.row_start(),
        row_count: work.row_count(),
        logical_j: logical_j_u32,
        blocks: output_blocks,
    })
}

fn checked_dot_output(accumulator: i128, coordinate: DotCoordinate) -> Result<i64, RacoError> {
    i64::try_from(accumulator).map_err(|_| RacoError::DotProductOverflow {
        block_index: coordinate.block_index,
        lane_id: coordinate.lane_id,
        local_row: coordinate.local_row,
        j: coordinate.j,
    })
}

#[cfg(test)]
mod tests;
