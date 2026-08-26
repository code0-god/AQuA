//! Candle-independent AQuA command and tensor metadata.

use std::{error::Error, fmt};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum AquaDType {
    F32,
    I8,
    I16,
    I32,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct TensorDesc {
    pub dtype: AquaDType,
    pub shape: Vec<usize>,
    pub len: usize,
}

impl TensorDesc {
    pub fn new(dtype: AquaDType, shape: Vec<usize>) -> Result<Self, TensorDescError> {
        let len = shape
            .iter()
            .try_fold(1_usize, |len, dim| len.checked_mul(*dim))
            .ok_or(TensorDescError::ElementCountOverflow)?;
        Ok(Self { dtype, shape, len })
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum TensorDescError {
    ElementCountOverflow,
}

impl fmt::Display for TensorDescError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ElementCountOverflow => formatter.write_str("tensor element count overflow"),
        }
    }
}

impl Error for TensorDescError {}
