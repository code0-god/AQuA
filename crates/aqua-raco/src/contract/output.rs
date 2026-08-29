use crate::{RacoError, RACO_MAX_LANES};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RacoBlockOutput {
    pub(crate) block_index: u32,
    pub(crate) active_lane_ids: [u8; RACO_MAX_LANES],
    pub(crate) active_lane_count: u8,
    pub(crate) row_count: u32,
    pub(crate) logical_j: u32,
    pub(crate) values: Vec<i64>,
}

impl RacoBlockOutput {
    pub const fn block_index(&self) -> u32 {
        self.block_index
    }

    pub fn active_lane_ids(&self) -> &[u8] {
        &self.active_lane_ids[..usize::from(self.active_lane_count)]
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

    pub fn value(
        &self,
        active_lane_position: usize,
        local_row: usize,
        j: usize,
    ) -> Result<i64, RacoError> {
        let lanes = self.active_lane_ids().len();
        let rows = usize::try_from(self.row_count).map_err(|_| RacoError::WorkOutputMismatch {
            reason: "row count does not fit usize",
        })?;
        let columns =
            usize::try_from(self.logical_j).map_err(|_| RacoError::WorkOutputMismatch {
                reason: "logical J does not fit usize",
            })?;
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
        if j >= columns {
            return Err(RacoError::IndexOutOfBounds {
                field: "J",
                index: j,
                len: columns,
            });
        }
        let index = active_lane_position
            .checked_mul(rows)
            .and_then(|value| value.checked_add(local_row))
            .and_then(|value| value.checked_mul(columns))
            .and_then(|value| value.checked_add(j))
            .ok_or(RacoError::ElementCountOverflow {
                field: "block output index",
            })?;
        self.values
            .get(index)
            .copied()
            .ok_or(RacoError::IndexOutOfBounds {
                field: "block output",
                index,
                len: self.values.len(),
            })
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RacoCompressedOutput {
    pub(crate) stripe_index: u32,
    pub(crate) row_start: u32,
    pub(crate) row_count: u32,
    pub(crate) logical_j: u32,
    pub(crate) blocks: Vec<RacoBlockOutput>,
}

impl RacoCompressedOutput {
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

    pub fn blocks(&self) -> &[RacoBlockOutput] {
        &self.blocks
    }
}
