use crate::MatrixWeightRole;
use std::collections::BTreeMap;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ShiftEncodingStats {
    pub(super) direct_bits: u8,
    pub(super) unique_count: usize,
    pub(super) lut_index_bits: u8,
}

impl ShiftEncodingStats {
    pub const fn direct_bits(self) -> u8 {
        self.direct_bits
    }

    pub const fn unique_count(self) -> usize {
        self.unique_count
    }

    pub const fn lut_index_bits(self) -> u8 {
        self.lut_index_bits
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Hp1TensorStats {
    pub(super) name: String,
    pub(super) role: MatrixWeightRole,
    pub(super) rows: usize,
    pub(super) k: usize,
    pub(super) block_count: usize,
    pub(super) zero_block_count: usize,
    pub(super) unique_left_shifts: Vec<u16>,
    pub(super) min_left_shift: Option<u16>,
    pub(super) max_left_shift: Option<u16>,
    pub(super) unique_row_scale_exponents: Vec<i16>,
}

impl Hp1TensorStats {
    pub fn name(&self) -> &str {
        &self.name
    }

    pub const fn role(&self) -> MatrixWeightRole {
        self.role
    }

    pub const fn rows(&self) -> usize {
        self.rows
    }

    pub const fn k(&self) -> usize {
        self.k
    }

    pub const fn block_count(&self) -> usize {
        self.block_count
    }

    pub const fn zero_block_count(&self) -> usize {
        self.zero_block_count
    }

    pub fn unique_left_shifts(&self) -> &[u16] {
        &self.unique_left_shifts
    }

    pub const fn min_left_shift(&self) -> Option<u16> {
        self.min_left_shift
    }

    pub const fn max_left_shift(&self) -> Option<u16> {
        self.max_left_shift
    }

    pub fn unique_row_scale_exponents(&self) -> &[i16] {
        &self.unique_row_scale_exponents
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Hp1WeightStats {
    pub(super) tensor_count: usize,
    pub(super) row_count: usize,
    pub(super) block_count: usize,
    pub(super) zero_block_count: usize,
    pub(super) nonzero_block_count: usize,
    pub(super) min_left_shift: Option<u16>,
    pub(super) max_left_shift: Option<u16>,
    pub(super) unique_left_shifts: Vec<u16>,
    pub(super) left_shift_histogram: BTreeMap<u16, usize>,
    pub(super) row_scale_exponent_min: Option<i16>,
    pub(super) row_scale_exponent_max: Option<i16>,
    pub(super) unique_row_scale_exponents: Vec<i16>,
    pub(super) row_scale_histogram: BTreeMap<i16, usize>,
    pub(super) zero_row_count: usize,
    pub(super) shift_encoding: ShiftEncodingStats,
    pub(super) tensor_stats: Vec<Hp1TensorStats>,
}

impl Hp1WeightStats {
    pub const fn tensor_count(&self) -> usize {
        self.tensor_count
    }

    pub const fn row_count(&self) -> usize {
        self.row_count
    }

    pub const fn block_count(&self) -> usize {
        self.block_count
    }

    pub const fn zero_block_count(&self) -> usize {
        self.zero_block_count
    }

    pub const fn nonzero_block_count(&self) -> usize {
        self.nonzero_block_count
    }

    pub const fn min_left_shift(&self) -> Option<u16> {
        self.min_left_shift
    }

    pub const fn max_left_shift(&self) -> Option<u16> {
        self.max_left_shift
    }

    pub fn unique_left_shifts(&self) -> &[u16] {
        &self.unique_left_shifts
    }

    pub const fn row_scale_exponent_min(&self) -> Option<i16> {
        self.row_scale_exponent_min
    }

    pub const fn row_scale_exponent_max(&self) -> Option<i16> {
        self.row_scale_exponent_max
    }

    pub fn unique_row_scale_exponents(&self) -> &[i16] {
        &self.unique_row_scale_exponents
    }

    pub fn left_shift_histogram(&self) -> &BTreeMap<u16, usize> {
        &self.left_shift_histogram
    }

    pub fn row_scale_histogram(&self) -> &BTreeMap<i16, usize> {
        &self.row_scale_histogram
    }

    pub const fn zero_row_count(&self) -> usize {
        self.zero_row_count
    }

    pub const fn shift_encoding(&self) -> ShiftEncodingStats {
        self.shift_encoding
    }

    pub fn tensor_stats(&self) -> &[Hp1TensorStats] {
        &self.tensor_stats
    }
}
