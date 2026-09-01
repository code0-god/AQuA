use crate::{classify_matrix_weight, MatrixWeightRole, WeightError};
use aqua_protocol::AQUA_BLOCK_SIZE;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct MatrixWeightShape {
    rows: usize,
    k: usize,
}

impl MatrixWeightShape {
    pub(crate) fn parse(shape: &[usize]) -> Result<Self, WeightError> {
        if shape.len() < 2 {
            return Err(WeightError::RankTooSmall { rank: shape.len() });
        }
        let k = shape[shape.len() - 1];
        if k == 0 {
            return Err(WeightError::EmptyK);
        }
        if !k.is_multiple_of(AQUA_BLOCK_SIZE) {
            return Err(WeightError::KNotBlockAligned {
                k,
                block_size: AQUA_BLOCK_SIZE,
            });
        }
        let rows = shape[..shape.len() - 1]
            .iter()
            .try_fold(1_usize, |rows, dim| rows.checked_mul(*dim))
            .ok_or(WeightError::ShapeElementCountOverflow)?;
        Ok(Self { rows, k })
    }

    pub const fn rows(self) -> usize {
        self.rows
    }

    pub const fn k(self) -> usize {
        self.k
    }

    pub const fn blocks_per_row(self) -> usize {
        self.k / AQUA_BLOCK_SIZE
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct MatrixWeightDescriptor {
    name: String,
    role: MatrixWeightRole,
    shape: MatrixWeightShape,
}

impl MatrixWeightDescriptor {
    pub(crate) fn parse(name: &str, shape: &[usize]) -> Result<Self, WeightError> {
        Ok(Self {
            name: name.to_owned(),
            role: classify_matrix_weight(name),
            shape: MatrixWeightShape::parse(shape)?,
        })
    }

    pub fn name(&self) -> &str {
        &self.name
    }

    pub const fn role(&self) -> MatrixWeightRole {
        self.role
    }

    pub const fn shape(&self) -> MatrixWeightShape {
        self.shape
    }
}
