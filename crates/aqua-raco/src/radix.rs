use crate::RacoError;
use aqua_exsia::ExsiaPrecision;
use std::ops::RangeInclusive;

pub const RACO_RESIDUAL_BITS: u8 = 21;
pub const RACO_RESIDUAL_MIN: i32 = -(1_i32 << (RACO_RESIDUAL_BITS - 1));
pub const RACO_RESIDUAL_MAX: i32 = (1_i32 << (RACO_RESIDUAL_BITS - 1)) - 1;
pub const RACO_MAX_LANES: usize = 8;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct RadixContract {
    radix: i64,
    lane_capacity: u8,
    digit_min: i32,
    digit_max: i32,
}

impl RadixContract {
    pub const fn radix(self) -> i64 {
        self.radix
    }

    pub const fn lane_capacity(self) -> u8 {
        self.lane_capacity
    }

    pub const fn digit_min(self) -> i32 {
        self.digit_min
    }

    pub const fn digit_max(self) -> i32 {
        self.digit_max
    }

    pub fn digit_range(self) -> RangeInclusive<i32> {
        self.digit_min..=self.digit_max
    }
}

pub const fn radix_contract(precision: ExsiaPrecision) -> RadixContract {
    match precision {
        ExsiaPrecision::I4 => RadixContract {
            radix: 16,
            lane_capacity: 8,
            digit_min: -8,
            digit_max: 7,
        },
        ExsiaPrecision::I8 => RadixContract {
            radix: 256,
            lane_capacity: 4,
            digit_min: -128,
            digit_max: 127,
        },
        ExsiaPrecision::I16 => RadixContract {
            radix: 65_536,
            lane_capacity: 2,
            digit_min: -32_768,
            digit_max: 32_767,
        },
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct BalancedDigits {
    digits: [i32; RACO_MAX_LANES],
    lane_capacity: u8,
    active_lane_mask: u8,
}

impl BalancedDigits {
    pub fn digits(&self) -> &[i32] {
        &self.digits[..usize::from(self.lane_capacity)]
    }

    pub const fn lane_capacity(&self) -> u8 {
        self.lane_capacity
    }

    pub const fn active_lane_mask(&self) -> u8 {
        self.active_lane_mask
    }

    pub const fn is_lane_active(&self, lane_id: u8) -> bool {
        lane_id < self.lane_capacity && self.active_lane_mask & (1_u8 << lane_id) != 0
    }

    pub fn active_lane_ids(&self) -> impl Iterator<Item = u8> + '_ {
        (0..self.lane_capacity).filter(|&lane_id| self.is_lane_active(lane_id))
    }
}

pub fn decompose_residual(
    residual: i32,
    precision: ExsiaPrecision,
) -> Result<BalancedDigits, RacoError> {
    if !(RACO_RESIDUAL_MIN..=RACO_RESIDUAL_MAX).contains(&residual) {
        return Err(RacoError::ResidualOutOfRange {
            value: residual,
            minimum: RACO_RESIDUAL_MIN,
            maximum: RACO_RESIDUAL_MAX,
        });
    }

    let contract = radix_contract(precision);
    let mut remaining = i64::from(residual);
    let mut digits = [0_i32; RACO_MAX_LANES];
    let mut active_lane_mask = 0_u8;

    for lane_id in 0..contract.lane_capacity() {
        let mut digit = remaining.rem_euclid(contract.radix());
        remaining = remaining.div_euclid(contract.radix());

        if digit >= contract.radix() / 2 {
            digit -= contract.radix();
            remaining += 1;
        }

        let digit = i32::try_from(digit).map_err(|_| RacoError::ResidualNotRepresentable {
            value: residual,
            precision,
        })?;
        if !contract.digit_range().contains(&digit) {
            return Err(RacoError::InvalidDigit {
                precision,
                value: digit,
            });
        }

        digits[usize::from(lane_id)] = digit;
        if digit != 0 {
            active_lane_mask |= 1_u8 << lane_id;
        }
    }

    if remaining != 0 {
        return Err(RacoError::ResidualNotRepresentable {
            value: residual,
            precision,
        });
    }

    Ok(BalancedDigits {
        digits,
        lane_capacity: contract.lane_capacity(),
        active_lane_mask,
    })
}

pub fn compose_digits(
    digits: &BalancedDigits,
    precision: ExsiaPrecision,
) -> Result<i64, RacoError> {
    let contract = radix_contract(precision);
    if digits.lane_capacity() != contract.lane_capacity() {
        return Err(RacoError::LaneCapacityMismatch {
            precision,
            expected: contract.lane_capacity(),
            actual: digits.lane_capacity(),
        });
    }

    let mut value = 0_i128;
    for lane_id in (0..contract.lane_capacity()).rev() {
        let digit = digits.digits[usize::from(lane_id)];
        if !contract.digit_range().contains(&digit) {
            return Err(RacoError::InvalidDigit {
                precision,
                value: digit,
            });
        }
        value = value * i128::from(contract.radix()) + i128::from(digit);
    }

    i64::try_from(value).map_err(|_| RacoError::DigitCompositionOverflow { precision })
}

#[cfg(test)]
mod tests;
