use crate::{radix_contract, RacoCompressedOutput, RacoError, RacoStripeWork};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RawRacoCorrection {
    pub(crate) stripe_index: u32,
    pub(crate) row_start: u32,
    pub(crate) row_count: u32,
    pub(crate) logical_j: u32,
    pub(crate) values: Vec<i64>,
}

impl RawRacoCorrection {
    pub const fn stripe_index(&self) -> u32 {
        self.stripe_index
    }

    pub const fn row_start(&self) -> u32 {
        self.row_start
    }

    pub const fn row_count(&self) -> u32 {
        self.row_count
    }

    pub const fn logical_j(&self) -> u32 {
        self.logical_j
    }

    pub fn values(&self) -> &[i64] {
        &self.values
    }

    pub fn value(&self, local_row: usize, j: usize) -> Result<i64, RacoError> {
        let rows = usize::try_from(self.row_count).map_err(|_| RacoError::WorkOutputMismatch {
            reason: "correction row count does not fit usize",
        })?;
        let columns =
            usize::try_from(self.logical_j).map_err(|_| RacoError::WorkOutputMismatch {
                reason: "correction logical J does not fit usize",
            })?;
        if local_row >= rows {
            return Err(RacoError::IndexOutOfBounds {
                field: "correction row",
                index: local_row,
                len: rows,
            });
        }
        if j >= columns {
            return Err(RacoError::IndexOutOfBounds {
                field: "correction J",
                index: j,
                len: columns,
            });
        }
        let index = local_row
            .checked_mul(columns)
            .and_then(|value| value.checked_add(j))
            .ok_or(RacoError::ElementCountOverflow {
                field: "correction index",
            })?;
        self.values
            .get(index)
            .copied()
            .ok_or(RacoError::IndexOutOfBounds {
                field: "correction",
                index,
                len: self.values.len(),
            })
    }
}

pub fn compose_correction(
    work: &RacoStripeWork,
    output: &RacoCompressedOutput,
) -> Result<RawRacoCorrection, RacoError> {
    if work.stripe_index() != output.stripe_index()
        || work.row_start() != output.row_start()
        || work.row_count() != output.row_count()
    {
        return Err(RacoError::WorkOutputMismatch {
            reason: "stripe metadata differs",
        });
    }
    if work.blocks().len() != output.blocks().len() {
        return Err(RacoError::WorkOutputMismatch {
            reason: "block count differs",
        });
    }

    let rows = usize::try_from(work.row_count()).map_err(|_| RacoError::WorkOutputMismatch {
        reason: "row count does not fit usize",
    })?;
    let columns =
        usize::try_from(output.logical_j()).map_err(|_| RacoError::WorkOutputMismatch {
            reason: "logical J does not fit usize",
        })?;
    if columns == 0 {
        return Err(RacoError::InvalidLogicalDimension {
            field: "J",
            value: 0,
        });
    }
    let correction_len = rows
        .checked_mul(columns)
        .ok_or(RacoError::ElementCountOverflow {
            field: "raw correction",
        })?;
    let mut correction = vec![0_i64; correction_len];
    let contract = radix_contract(work.precision());

    for (work_block, output_block) in work.blocks().iter().zip(output.blocks()) {
        if work_block.block_index() != output_block.block_index() {
            return Err(RacoError::WorkOutputMismatch {
                reason: "block index differs",
            });
        }
        if work_block.active_lane_ids() != output_block.active_lane_ids() {
            return Err(RacoError::WorkOutputMismatch {
                reason: "active lane IDs differ",
            });
        }
        if work_block.row_count() != output_block.row_count()
            || output_block.row_count() != work.row_count()
            || output_block.logical_j() != output.logical_j()
        {
            return Err(RacoError::WorkOutputMismatch {
                reason: "block output shape differs",
            });
        }

        for local_row in 0..rows {
            for j in 0..columns {
                let mut block_value = 0_i128;
                for lane_id in (0..contract.lane_capacity()).rev() {
                    let lane_output = match output_block
                        .active_lane_ids()
                        .iter()
                        .position(|&active_lane_id| active_lane_id == lane_id)
                    {
                        Some(position) => output_block.value(position, local_row, j)?,
                        None => 0,
                    };
                    block_value =
                        block_value * i128::from(contract.radix()) + i128::from(lane_output);
                    i64::try_from(block_value).map_err(|_| RacoError::CompositionOverflow {
                        block_index: work_block.block_index(),
                        local_row,
                        j,
                    })?;
                }

                let correction_index = local_row
                    .checked_mul(columns)
                    .and_then(|value| value.checked_add(j))
                    .ok_or(RacoError::ElementCountOverflow {
                        field: "correction index",
                    })?;
                let combined = i128::from(correction[correction_index])
                    .checked_add(block_value)
                    .ok_or(RacoError::CorrectionOverflow { local_row, j })?;
                correction[correction_index] = i64::try_from(combined)
                    .map_err(|_| RacoError::CorrectionOverflow { local_row, j })?;
            }
        }
    }

    Ok(RawRacoCorrection {
        stripe_index: work.stripe_index(),
        row_start: work.row_start(),
        row_count: work.row_count(),
        logical_j: output.logical_j(),
        values: correction,
    })
}

#[cfg(test)]
mod tests;
