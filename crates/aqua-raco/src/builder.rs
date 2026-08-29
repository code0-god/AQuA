use crate::{
    decompose_residual, radix_contract, RacoBlockWork, RacoDigitValues, RacoError, RacoStripeWork,
    RACO_MAX_LANES,
};
use aqua_exsia::{ExsiaPrecision, ResidualStripe};
use aqua_protocol::AQUA_BLOCK_SIZE;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct StripeMetadata {
    stripe_index: usize,
    row_start: usize,
    row_count: usize,
    logical_k: usize,
}

struct PendingBlock {
    k_mask: u32,
    lane_mask: u8,
    seen_k_by_row: Vec<u32>,
    digits: Vec<i32>,
}

impl PendingBlock {
    fn new(lane_capacity: u8, row_count: usize) -> Result<Self, RacoError> {
        let digit_count = usize::from(lane_capacity)
            .checked_mul(row_count)
            .and_then(|len| len.checked_mul(AQUA_BLOCK_SIZE))
            .ok_or(RacoError::ElementCountOverflow {
                field: "pending digit payload",
            })?;
        Ok(Self {
            k_mask: 0,
            lane_mask: 0,
            seen_k_by_row: vec![0; row_count],
            digits: vec![0; digit_count],
        })
    }

    fn compact(
        self,
        block_index: u32,
        precision: ExsiaPrecision,
    ) -> Result<RacoBlockWork, RacoError> {
        let mut compact_k = [0_u8; AQUA_BLOCK_SIZE];
        let mut compact_k_count = 0_usize;
        for local_k in 0..AQUA_BLOCK_SIZE {
            if self.k_mask & (1_u32 << local_k) != 0 {
                compact_k[compact_k_count] =
                    u8::try_from(local_k).map_err(|_| RacoError::InvalidCompactK {
                        block_index,
                        value: u8::MAX,
                    })?;
                compact_k_count += 1;
            }
        }

        let lane_capacity = radix_contract(precision).lane_capacity();
        let mut active_lane_ids = [0_u8; RACO_MAX_LANES];
        let mut active_lane_count = 0_usize;
        for lane_id in 0..lane_capacity {
            if self.lane_mask & (1_u8 << lane_id) != 0 {
                active_lane_ids[active_lane_count] = lane_id;
                active_lane_count += 1;
            }
        }

        let row_count = self.seen_k_by_row.len();
        let payload_len = active_lane_count
            .checked_mul(row_count)
            .and_then(|len| len.checked_mul(compact_k_count))
            .ok_or(RacoError::ElementCountOverflow {
                field: "compacted digit payload",
            })?;
        let mut compacted = RacoDigitValues::zeros(precision, payload_len);
        let mut output_index = 0_usize;
        for &lane_id in &active_lane_ids[..active_lane_count] {
            for local_row in 0..row_count {
                for &local_k in &compact_k[..compact_k_count] {
                    let source_index = usize::from(lane_id)
                        .checked_mul(row_count)
                        .and_then(|value| value.checked_add(local_row))
                        .and_then(|value| value.checked_mul(AQUA_BLOCK_SIZE))
                        .and_then(|value| value.checked_add(usize::from(local_k)))
                        .ok_or(RacoError::ElementCountOverflow {
                            field: "pending digit index",
                        })?;
                    let digit = self.digits.get(source_index).copied().ok_or(
                        RacoError::IndexOutOfBounds {
                            field: "pending digit payload",
                            index: source_index,
                            len: self.digits.len(),
                        },
                    )?;
                    compacted.set_i32(output_index, digit)?;
                    output_index += 1;
                }
            }
        }

        Ok(RacoBlockWork {
            block_index,
            compact_k,
            compact_k_count: u8::try_from(compact_k_count).map_err(|_| {
                RacoError::ElementCountOverflow {
                    field: "compact K count",
                }
            })?,
            active_lane_ids,
            active_lane_count: u8::try_from(active_lane_count).map_err(|_| {
                RacoError::ElementCountOverflow {
                    field: "active lane count",
                }
            })?,
            row_count: u32_field("row count", row_count)?,
            digits: compacted,
        })
    }
}

pub fn build_stripe_work(
    residuals: &ResidualStripe,
    precision: ExsiaPrecision,
) -> Result<Option<RacoStripeWork>, RacoError> {
    build_from_events(
        StripeMetadata {
            stripe_index: residuals.stripe_index(),
            row_start: residuals.row_start(),
            row_count: residuals.row_count(),
            logical_k: residuals.logical_k(),
        },
        precision,
        residuals
            .iter()
            .map(|event| (event.local_row(), event.k(), event.residual())),
    )
}

fn build_from_events(
    metadata: StripeMetadata,
    precision: ExsiaPrecision,
    events: impl IntoIterator<Item = (usize, usize, i32)>,
) -> Result<Option<RacoStripeWork>, RacoError> {
    if metadata.row_count == 0 {
        return Err(RacoError::InvalidLogicalDimension {
            field: "row count",
            value: 0,
        });
    }
    if metadata.logical_k == 0 {
        return Err(RacoError::InvalidLogicalDimension {
            field: "K",
            value: 0,
        });
    }

    let lane_capacity = radix_contract(precision).lane_capacity();
    let block_count = metadata.logical_k.div_ceil(AQUA_BLOCK_SIZE);
    let mut pending_blocks = std::iter::repeat_with(|| None)
        .take(block_count)
        .collect::<Vec<Option<PendingBlock>>>();
    let mut residual_event_count = 0_usize;

    for (local_row, k, residual) in events {
        if local_row >= metadata.row_count {
            return Err(RacoError::ResidualRowOutOfBounds {
                local_row,
                row_count: metadata.row_count,
            });
        }
        if k >= metadata.logical_k {
            return Err(RacoError::ResidualKOutOfBounds {
                k,
                logical_k: metadata.logical_k,
            });
        }
        if residual == 0 {
            return Err(RacoError::ZeroResidual { local_row, k });
        }

        let decomposed = decompose_residual(residual, precision)?;
        let block_index = k / AQUA_BLOCK_SIZE;
        let local_k = k % AQUA_BLOCK_SIZE;
        let slot = pending_blocks
            .get_mut(block_index)
            .ok_or(RacoError::ResidualKOutOfBounds {
                k,
                logical_k: metadata.logical_k,
            })?;
        if slot.is_none() {
            *slot = Some(PendingBlock::new(lane_capacity, metadata.row_count)?);
        }
        let pending = slot.as_mut().ok_or(RacoError::WorkOutputMismatch {
            reason: "pending block allocation failed",
        })?;
        let coordinate_mask = 1_u32 << local_k;
        let seen =
            pending
                .seen_k_by_row
                .get_mut(local_row)
                .ok_or(RacoError::ResidualRowOutOfBounds {
                    local_row,
                    row_count: metadata.row_count,
                })?;
        if *seen & coordinate_mask != 0 {
            return Err(RacoError::DuplicateResidualCoordinate { local_row, k });
        }
        *seen |= coordinate_mask;

        for lane_id in decomposed.active_lane_ids() {
            let digit = decomposed
                .digits()
                .get(usize::from(lane_id))
                .copied()
                .ok_or(RacoError::InvalidLaneId { precision, lane_id })?;
            let digit_index = usize::from(lane_id)
                .checked_mul(metadata.row_count)
                .and_then(|value| value.checked_add(local_row))
                .and_then(|value| value.checked_mul(AQUA_BLOCK_SIZE))
                .and_then(|value| value.checked_add(local_k))
                .ok_or(RacoError::ElementCountOverflow {
                    field: "pending digit index",
                })?;
            let digit_payload_len = pending.digits.len();
            let slot = pending
                .digits
                .get_mut(digit_index)
                .ok_or(RacoError::IndexOutOfBounds {
                    field: "pending digit payload",
                    index: digit_index,
                    len: digit_payload_len,
                })?;
            *slot = digit;
            pending.k_mask |= coordinate_mask;
            pending.lane_mask |= 1_u8 << lane_id;
        }

        residual_event_count =
            residual_event_count
                .checked_add(1)
                .ok_or(RacoError::ElementCountOverflow {
                    field: "residual event count",
                })?;
    }

    if residual_event_count == 0 {
        return Ok(None);
    }

    let mut blocks = Vec::new();
    for (block_index, pending) in pending_blocks.into_iter().enumerate() {
        if let Some(pending) = pending {
            blocks.push(pending.compact(u32_field("block index", block_index)?, precision)?);
        }
    }

    Ok(Some(RacoStripeWork {
        stripe_index: u32_field("stripe index", metadata.stripe_index)?,
        row_start: u32_field("row start", metadata.row_start)?,
        row_count: u32_field("row count", metadata.row_count)?,
        logical_k: u32_field("logical K", metadata.logical_k)?,
        precision,
        residual_event_count,
        blocks,
    }))
}

fn u32_field(field: &'static str, value: usize) -> Result<u32, RacoError> {
    u32::try_from(value).map_err(|_| RacoError::IndexDoesNotFitU32 { field, value })
}

#[cfg(test)]
mod tests;
