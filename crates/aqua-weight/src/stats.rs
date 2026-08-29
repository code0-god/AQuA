use crate::{AquaWeightRegistry, Hp1BlockScale, Hp1MatrixWeight, WeightError};
use std::collections::BTreeMap;

mod contracts;

pub use contracts::{Hp1TensorStats, Hp1WeightStats, ShiftEncodingStats};

impl ShiftEncodingStats {
    fn from_histogram(histogram: &BTreeMap<u16, usize>) -> Result<Self, WeightError> {
        let direct_width = histogram
            .last_key_value()
            .map_or(0, |(maximum, _)| u16::BITS - maximum.leading_zeros());
        let unique_count = histogram.len();
        let lut_width = if unique_count <= 1 {
            0
        } else {
            usize::BITS - (unique_count - 1).leading_zeros()
        };
        Ok(Self {
            direct_bits: u8::try_from(direct_width).map_err(|_| WeightError::StatisticsOverflow)?,
            unique_count,
            lut_index_bits: u8::try_from(lut_width).map_err(|_| WeightError::StatisticsOverflow)?,
        })
    }
}

impl Hp1TensorStats {
    fn from_weight(weight: &Hp1MatrixWeight) -> Self {
        let mut shifts = BTreeMap::new();
        let mut zero_block_count = 0;
        for scale in weight.block_scales() {
            match scale {
                Hp1BlockScale::ZeroBlock => zero_block_count += 1,
                Hp1BlockScale::LeftShift(shift) => {
                    shifts.insert(*shift, ());
                }
            }
        }
        let row_exponents = weight
            .row_scales()
            .iter()
            .filter_map(|scale| scale.exponent())
            .collect::<std::collections::BTreeSet<_>>();
        Self {
            name: weight.descriptor().name().to_owned(),
            role: weight.descriptor().role(),
            rows: weight.descriptor().shape().rows(),
            k: weight.descriptor().shape().k(),
            block_count: weight.block_scales().len(),
            zero_block_count,
            min_left_shift: shifts.first_key_value().map(|(shift, ())| *shift),
            max_left_shift: shifts.last_key_value().map(|(shift, ())| *shift),
            unique_left_shifts: shifts.into_keys().collect(),
            unique_row_scale_exponents: row_exponents.into_iter().collect(),
        }
    }
}

impl Hp1WeightStats {
    pub fn from_registry(registry: &AquaWeightRegistry) -> Result<Self, WeightError> {
        let mut row_count = 0_usize;
        let mut block_count = 0_usize;
        let mut zero_block_count = 0_usize;
        let mut left_shift_histogram = BTreeMap::new();
        let mut row_scale_histogram = BTreeMap::new();
        let mut zero_row_count = 0_usize;
        let mut tensor_stats = Vec::with_capacity(registry.len());

        for (_, weight) in registry.iter() {
            row_count = row_count
                .checked_add(weight.descriptor().shape().rows())
                .ok_or(WeightError::StatisticsOverflow)?;
            block_count = block_count
                .checked_add(weight.block_scales().len())
                .ok_or(WeightError::StatisticsOverflow)?;
            for scale in weight.block_scales() {
                match scale {
                    Hp1BlockScale::ZeroBlock => {
                        zero_block_count = zero_block_count
                            .checked_add(1)
                            .ok_or(WeightError::StatisticsOverflow)?;
                    }
                    Hp1BlockScale::LeftShift(shift) => {
                        let count = left_shift_histogram.entry(*shift).or_insert(0_usize);
                        *count = count
                            .checked_add(1)
                            .ok_or(WeightError::StatisticsOverflow)?;
                    }
                }
            }
            for scale in weight.row_scales() {
                match scale.exponent() {
                    Some(exponent) => {
                        let count = row_scale_histogram.entry(exponent).or_insert(0_usize);
                        *count = count
                            .checked_add(1)
                            .ok_or(WeightError::StatisticsOverflow)?;
                    }
                    None => {
                        zero_row_count = zero_row_count
                            .checked_add(1)
                            .ok_or(WeightError::StatisticsOverflow)?;
                    }
                }
            }
            tensor_stats.push(Hp1TensorStats::from_weight(weight));
        }
        let nonzero_block_count = block_count
            .checked_sub(zero_block_count)
            .ok_or(WeightError::StatisticsOverflow)?;
        let shift_encoding = ShiftEncodingStats::from_histogram(&left_shift_histogram)?;
        Ok(Self {
            tensor_count: registry.len(),
            row_count,
            block_count,
            zero_block_count,
            nonzero_block_count,
            min_left_shift: left_shift_histogram
                .first_key_value()
                .map(|(shift, _)| *shift),
            max_left_shift: left_shift_histogram
                .last_key_value()
                .map(|(shift, _)| *shift),
            unique_left_shifts: left_shift_histogram.keys().copied().collect(),
            row_scale_exponent_min: row_scale_histogram
                .first_key_value()
                .map(|(exponent, _)| *exponent),
            row_scale_exponent_max: row_scale_histogram
                .last_key_value()
                .map(|(exponent, _)| *exponent),
            unique_row_scale_exponents: row_scale_histogram.keys().copied().collect(),
            left_shift_histogram,
            row_scale_histogram,
            zero_row_count,
            shift_encoding,
            tensor_stats,
        })
    }
}
