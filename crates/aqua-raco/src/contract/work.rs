use super::RacoDigitValues;
use crate::{RacoError, RACO_MAX_LANES};
use aqua_exsia::ExsiaPrecision;
use aqua_protocol::AQUA_BLOCK_SIZE;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RacoBlockWork {
    pub(crate) block_index: u32,
    pub(crate) compact_k: [u8; AQUA_BLOCK_SIZE],
    pub(crate) compact_k_count: u8,
    pub(crate) active_lane_ids: [u8; RACO_MAX_LANES],
    pub(crate) active_lane_count: u8,
    pub(crate) row_count: u32,
    pub(crate) digits: RacoDigitValues,
}

impl RacoBlockWork {
    pub const fn block_index(&self) -> u32 {
        self.block_index
    }

    pub fn compact_k(&self) -> &[u8] {
        &self.compact_k[..usize::from(self.compact_k_count)]
    }

    pub fn active_lane_ids(&self) -> &[u8] {
        &self.active_lane_ids[..usize::from(self.active_lane_count)]
    }

    pub const fn row_count(&self) -> u32 {
        self.row_count
    }

    pub const fn precision(&self) -> ExsiaPrecision {
        self.digits.precision()
    }

    pub const fn digits(&self) -> &RacoDigitValues {
        &self.digits
    }

    pub fn digit(
        &self,
        active_lane_position: usize,
        local_row: usize,
        compact_k_position: usize,
    ) -> Result<i32, RacoError> {
        let lanes = self.active_lane_ids().len();
        let rows = usize::try_from(self.row_count).map_err(|_| RacoError::WorkOutputMismatch {
            reason: "row count does not fit usize",
        })?;
        let compact = self.compact_k().len();
        if active_lane_position >= lanes {
            return Err(RacoError::IndexOutOfBounds {
                field: "active lane position",
                index: active_lane_position,
                len: lanes,
            });
        }
        if local_row >= rows {
            return Err(RacoError::IndexOutOfBounds {
                field: "local row",
                index: local_row,
                len: rows,
            });
        }
        if compact_k_position >= compact {
            return Err(RacoError::IndexOutOfBounds {
                field: "compact K position",
                index: compact_k_position,
                len: compact,
            });
        }
        let index = active_lane_position
            .checked_mul(rows)
            .and_then(|value| value.checked_add(local_row))
            .and_then(|value| value.checked_mul(compact))
            .and_then(|value| value.checked_add(compact_k_position))
            .ok_or(RacoError::ElementCountOverflow {
                field: "digit payload index",
            })?;
        self.digits.get_i32(index)
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RacoStripeWork {
    pub(crate) stripe_index: u32,
    pub(crate) row_start: u32,
    pub(crate) row_count: u32,
    pub(crate) logical_k: u32,
    pub(crate) precision: ExsiaPrecision,
    pub(crate) residual_event_count: usize,
    pub(crate) blocks: Vec<RacoBlockWork>,
}

impl RacoStripeWork {
    pub const fn stripe_index(&self) -> u32 {
        self.stripe_index
    }

    pub const fn row_start(&self) -> u32 {
        self.row_start
    }

    pub const fn row_count(&self) -> u32 {
        self.row_count
    }

    pub const fn logical_k(&self) -> u32 {
        self.logical_k
    }

    pub const fn precision(&self) -> ExsiaPrecision {
        self.precision
    }

    pub const fn residual_event_count(&self) -> usize {
        self.residual_event_count
    }

    pub fn blocks(&self) -> &[RacoBlockWork] {
        &self.blocks
    }
}
