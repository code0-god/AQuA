use crate::{MatrixWeightDescriptor, WeightError};
use aqua_protocol::AQUA_BLOCK_SIZE;

pub const HP1_BLOCK_BYTES: usize = 40;
const HP1_CODE_BYTES: usize = 32;
const HP1_SHIFT_OFFSET: usize = 32;
const HP1_PADDING_OFFSET: usize = 34;
const HP1_ROW_SCALE_OFFSET: usize = 36;

const _: () = assert!(HP1_CODE_BYTES == AQUA_BLOCK_SIZE);

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum Hp1BlockScale {
    ZeroBlock,
    LeftShift(u16),
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Hp1RowScale {
    bits: u32,
    exponent: Option<i16>,
}

impl Hp1RowScale {
    fn parse(row: usize, bits: u32) -> Result<Self, WeightError> {
        if bits == 0 {
            return Ok(Self {
                bits,
                exponent: None,
            });
        }
        let value = f32::from_bits(bits);
        let raw_exponent = (bits >> 23) & 0xff;
        let mantissa = bits & 0x7f_ffff;
        if !value.is_finite() || value <= 0.0 {
            return Err(WeightError::InvalidRowScale { row, bits });
        }
        let exponent = if raw_exponent == 0 {
            if mantissa.count_ones() != 1 {
                return Err(WeightError::InvalidRowScale { row, bits });
            }
            let bit = i16::try_from(mantissa.trailing_zeros())
                .map_err(|_| WeightError::InvalidRowScale { row, bits })?;
            bit - 149
        } else {
            if mantissa != 0 {
                return Err(WeightError::InvalidRowScale { row, bits });
            }
            i16::try_from(raw_exponent).map_err(|_| WeightError::InvalidRowScale { row, bits })?
                - 127
        };
        Ok(Self {
            bits,
            exponent: Some(exponent),
        })
    }

    pub const fn bits(self) -> u32 {
        self.bits
    }

    pub const fn exponent(self) -> Option<i16> {
        self.exponent
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Hp1MatrixWeight {
    descriptor: MatrixWeightDescriptor,
    codes: Vec<i8>,
    block_scales: Vec<Hp1BlockScale>,
    row_scales: Vec<Hp1RowScale>,
}

impl Hp1MatrixWeight {
    pub const fn descriptor(&self) -> &MatrixWeightDescriptor {
        &self.descriptor
    }

    pub fn codes(&self) -> &[i8] {
        &self.codes
    }

    pub fn block_scales(&self) -> &[Hp1BlockScale] {
        &self.block_scales
    }

    pub fn row_scales(&self) -> &[Hp1RowScale] {
        &self.row_scales
    }
}

pub fn parse_h1_matrix_weight(
    _name: &str,
    _shape: &[usize],
    _raw_data: &[u8],
) -> Result<Hp1MatrixWeight, WeightError> {
    Err(WeightError::UnsupportedQ8H1)
}

pub fn parse_hp1_matrix_weight(
    name: &str,
    shape: &[usize],
    raw_data: &[u8],
) -> Result<Hp1MatrixWeight, WeightError> {
    let descriptor = MatrixWeightDescriptor::parse(name, shape)?;
    let matrix_shape = descriptor.shape();
    let block_count = matrix_shape
        .rows()
        .checked_mul(matrix_shape.blocks_per_row())
        .ok_or(WeightError::PayloadLengthOverflow)?;
    let expected_bytes = block_count
        .checked_mul(HP1_BLOCK_BYTES)
        .ok_or(WeightError::PayloadLengthOverflow)?;
    if raw_data.len() != expected_bytes {
        return Err(WeightError::PayloadLengthMismatch {
            expected: expected_bytes,
            actual: raw_data.len(),
        });
    }
    let code_count = matrix_shape
        .rows()
        .checked_mul(matrix_shape.k())
        .ok_or(WeightError::ShapeElementCountOverflow)?;
    let mut codes = Vec::with_capacity(code_count);
    let mut block_scales = Vec::with_capacity(block_count);
    let mut row_scales = Vec::with_capacity(matrix_shape.rows());

    for row in 0..matrix_shape.rows() {
        let mut row_scale_bits = None;
        let mut has_left_shift = false;
        let row_block_start = block_scales.len();
        for block in 0..matrix_shape.blocks_per_row() {
            let block_index = row
                .checked_mul(matrix_shape.blocks_per_row())
                .and_then(|index| index.checked_add(block))
                .ok_or(WeightError::PayloadLengthOverflow)?;
            let start = block_index
                .checked_mul(HP1_BLOCK_BYTES)
                .ok_or(WeightError::PayloadLengthOverflow)?;
            let raw = &raw_data[start..start + HP1_BLOCK_BYTES];
            let mut block_codes = [0_i8; AQUA_BLOCK_SIZE];
            for (code, byte) in block_codes.iter_mut().zip(&raw[..HP1_CODE_BYTES]) {
                *code = i8::from_le_bytes([*byte]);
            }
            let shift = i16::from_le_bytes([raw[HP1_SHIFT_OFFSET], raw[HP1_SHIFT_OFFSET + 1]]);
            let padding = [raw[HP1_PADDING_OFFSET], raw[HP1_PADDING_OFFSET + 1]];
            if padding != [0, 0] {
                return Err(WeightError::NonzeroPadding {
                    row,
                    block,
                    padding,
                });
            }
            let scale = match shift {
                i16::MIN => {
                    if block_codes.iter().any(|code| *code != 0) {
                        return Err(WeightError::InvalidZeroBlockEncoding { row, block });
                    }
                    Hp1BlockScale::ZeroBlock
                }
                0..=i16::MAX => {
                    if let Some(index) = block_codes.iter().position(|code| *code == i8::MIN) {
                        return Err(WeightError::InvalidCode {
                            row,
                            block,
                            index,
                            value: i8::MIN,
                        });
                    }
                    has_left_shift = true;
                    Hp1BlockScale::LeftShift(u16::try_from(shift).map_err(|_| {
                        WeightError::NegativeBlockShift {
                            row,
                            block,
                            value: shift,
                        }
                    })?)
                }
                _ => {
                    return Err(WeightError::NegativeBlockShift {
                        row,
                        block,
                        value: shift,
                    })
                }
            };
            let bits = u32::from_le_bytes([
                raw[HP1_ROW_SCALE_OFFSET],
                raw[HP1_ROW_SCALE_OFFSET + 1],
                raw[HP1_ROW_SCALE_OFFSET + 2],
                raw[HP1_ROW_SCALE_OFFSET + 3],
            ]);
            if let Some(expected_bits) = row_scale_bits {
                if bits != expected_bits {
                    return Err(WeightError::InconsistentRowScale {
                        row,
                        expected_bits,
                        actual_bits: bits,
                    });
                }
            } else {
                row_scale_bits = Some(bits);
            }
            codes.extend_from_slice(&block_codes);
            block_scales.push(scale);
        }
        let bits = row_scale_bits.ok_or(WeightError::PayloadLengthMismatch {
            expected: expected_bytes,
            actual: raw_data.len(),
        })?;
        let row_scale = Hp1RowScale::parse(row, bits)?;
        match (row_scale.exponent(), has_left_shift) {
            (None, true) => return Err(WeightError::ZeroScaleWithNonzeroBlock { row }),
            (Some(_), false) => return Err(WeightError::NonzeroScaleForZeroRow { row }),
            (Some(row_exponent), true) => {
                for (block, scale) in block_scales[row_block_start..].iter().enumerate() {
                    if let Hp1BlockScale::LeftShift(shift) = scale {
                        let effective_exponent = i32::from(row_exponent) + i32::from(*shift);
                        if !(-149..=127).contains(&effective_exponent) {
                            return Err(WeightError::InvalidEffectiveBlockScale {
                                row,
                                block,
                                row_exponent,
                                shift: *shift,
                            });
                        }
                    }
                }
            }
            (None, false) => {}
        }
        row_scales.push(row_scale);
    }

    Ok(Hp1MatrixWeight {
        descriptor,
        codes,
        block_scales,
        row_scales,
    })
}
