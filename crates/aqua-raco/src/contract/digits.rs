use crate::RacoError;
use aqua_exsia::ExsiaPrecision;

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RacoDigitValues {
    storage: DigitStorage,
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum DigitStorage {
    I4(Vec<i8>),
    I8(Vec<i8>),
    I16(Vec<i16>),
}

impl RacoDigitValues {
    pub(crate) fn zeros(precision: ExsiaPrecision, len: usize) -> Self {
        let storage = match precision {
            ExsiaPrecision::I4 => DigitStorage::I4(vec![0; len]),
            ExsiaPrecision::I8 => DigitStorage::I8(vec![0; len]),
            ExsiaPrecision::I16 => DigitStorage::I16(vec![0; len]),
        };
        Self { storage }
    }

    #[cfg(test)]
    pub(crate) fn from_i32(precision: ExsiaPrecision, values: &[i32]) -> Result<Self, RacoError> {
        let mut digits = Self::zeros(precision, values.len());
        for (index, &value) in values.iter().enumerate() {
            digits.set_i32(index, value)?;
        }
        Ok(digits)
    }

    pub const fn precision(&self) -> ExsiaPrecision {
        match &self.storage {
            DigitStorage::I4(_) => ExsiaPrecision::I4,
            DigitStorage::I8(_) => ExsiaPrecision::I8,
            DigitStorage::I16(_) => ExsiaPrecision::I16,
        }
    }

    pub fn len(&self) -> usize {
        match &self.storage {
            DigitStorage::I4(values) | DigitStorage::I8(values) => values.len(),
            DigitStorage::I16(values) => values.len(),
        }
    }

    pub fn is_empty(&self) -> bool {
        self.len() == 0
    }

    pub(crate) fn set_i32(&mut self, index: usize, value: i32) -> Result<(), RacoError> {
        let precision = self.precision();
        match &mut self.storage {
            DigitStorage::I4(values) => {
                if !(-8..=7).contains(&value) {
                    return Err(RacoError::InvalidDigit { precision, value });
                }
                let slot = digit_slot_mut(values, index)?;
                *slot = i8::try_from(value)
                    .map_err(|_| RacoError::InvalidDigit { precision, value })?;
            }
            DigitStorage::I8(values) => {
                let slot = digit_slot_mut(values, index)?;
                *slot = i8::try_from(value)
                    .map_err(|_| RacoError::InvalidDigit { precision, value })?;
            }
            DigitStorage::I16(values) => {
                let slot = digit_slot_mut(values, index)?;
                *slot = i16::try_from(value)
                    .map_err(|_| RacoError::InvalidDigit { precision, value })?;
            }
        }
        Ok(())
    }

    pub fn get_i32(&self, index: usize) -> Result<i32, RacoError> {
        match &self.storage {
            DigitStorage::I4(values) | DigitStorage::I8(values) => values
                .get(index)
                .copied()
                .map(i32::from)
                .ok_or(RacoError::IndexOutOfBounds {
                    field: "digit payload",
                    index,
                    len: values.len(),
                }),
            DigitStorage::I16(values) => {
                values
                    .get(index)
                    .copied()
                    .map(i32::from)
                    .ok_or(RacoError::IndexOutOfBounds {
                        field: "digit payload",
                        index,
                        len: values.len(),
                    })
            }
        }
    }
}

fn digit_slot_mut<T>(values: &mut [T], index: usize) -> Result<&mut T, RacoError> {
    let len = values.len();
    values.get_mut(index).ok_or(RacoError::IndexOutOfBounds {
        field: "digit payload",
        index,
        len,
    })
}
