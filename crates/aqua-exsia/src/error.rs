use aqua_runtime::RuntimeError;
use std::{error::Error, fmt};

#[derive(Debug)]
pub enum ExsiaError {
    InvalidInput(RuntimeError),
    ReferenceNotImplemented,
}

impl fmt::Display for ExsiaError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidInput(error) => {
                write!(formatter, "invalid ExSIA input: {error}")
            }
            Self::ReferenceNotImplemented => {
                formatter.write_str("canonical software ExSIA reference is not implemented yet")
            }
        }
    }
}

impl Error for ExsiaError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::InvalidInput(error) => Some(error),
            Self::ReferenceNotImplemented => None,
        }
    }
}

impl From<RuntimeError> for ExsiaError {
    fn from(error: RuntimeError) -> Self {
        Self::InvalidInput(error)
    }
}
