use aqua_runtime::{ExecutionPlanError, RuntimeError};
use std::{error::Error, fmt};

#[derive(Debug)]
pub enum ExsiaError {
    InvalidInput(RuntimeError),
    InvalidExecutionPlan(ExecutionPlanError),
    InvalidBlockLength {
        len: usize,
        block_size: usize,
    },
    InvalidOutputElementCount {
        expected: usize,
        actual: usize,
    },
    InvalidStripeThetaCount {
        expected: usize,
        actual: usize,
    },
    InvalidStripeBlockCount {
        stripe_index: usize,
        expected: usize,
        actual: usize,
    },
    InvalidStripeBlockWidth {
        stripe_index: usize,
        local_block_index: usize,
        expected: usize,
        actual: usize,
    },
    InvalidStripeBlockMask {
        stripe_index: usize,
        local_block_index: usize,
        valid_element_count: usize,
        mask: u32,
    },
}

impl fmt::Display for ExsiaError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::InvalidInput(error) => {
                write!(formatter, "invalid ExSIA input: {error}")
            }
            Self::InvalidExecutionPlan(error) => {
                write!(formatter, "invalid ExSIA execution plan: {error}")
            }
            Self::InvalidBlockLength { len, block_size } => {
                write!(
                    formatter,
                    "invalid ExSIA block length {len}; block size is {block_size}"
                )
            }
            Self::InvalidOutputElementCount { expected, actual } => write!(
                formatter,
                "ExSIA output element count mismatch: expected {expected}, got {actual}"
            ),
            Self::InvalidStripeThetaCount { expected, actual } => write!(
                formatter,
                "ExSIA stripe-theta count mismatch: expected {expected}, got {actual}"
            ),
            Self::InvalidStripeBlockCount {
                stripe_index,
                expected,
                actual,
            } => write!(
                formatter,
                "stripe {stripe_index} block count mismatch: expected {expected}, got {actual}"
            ),
            Self::InvalidStripeBlockWidth {
                stripe_index,
                local_block_index,
                expected,
                actual,
            } => write!(
                formatter,
                "stripe {stripe_index} block {local_block_index} width mismatch: expected {expected}, got {actual}"
            ),
            Self::InvalidStripeBlockMask {
                stripe_index,
                local_block_index,
                valid_element_count,
                mask,
            } => write!(
                formatter,
                "stripe {stripe_index} block {local_block_index} mask {mask:#010x} exceeds {valid_element_count} logical elements"
            ),
        }
    }
}

impl Error for ExsiaError {
    fn source(&self) -> Option<&(dyn Error + 'static)> {
        match self {
            Self::InvalidInput(error) => Some(error),
            Self::InvalidExecutionPlan(error) => Some(error),
            Self::InvalidBlockLength { .. }
            | Self::InvalidOutputElementCount { .. }
            | Self::InvalidStripeThetaCount { .. }
            | Self::InvalidStripeBlockCount { .. }
            | Self::InvalidStripeBlockWidth { .. }
            | Self::InvalidStripeBlockMask { .. } => None,
        }
    }
}

impl From<RuntimeError> for ExsiaError {
    fn from(error: RuntimeError) -> Self {
        Self::InvalidInput(error)
    }
}

impl From<ExecutionPlanError> for ExsiaError {
    fn from(error: ExecutionPlanError) -> Self {
        Self::InvalidExecutionPlan(error)
    }
}

#[cfg(test)]
mod tests {
    use super::ExsiaError;
    use aqua_runtime::ExecutionPlanError;
    use std::error::Error;

    #[test]
    fn converts_execution_plan_error_with_source() {
        // Given
        let plan_error = ExecutionPlanError::ZeroK;

        // When
        let error = ExsiaError::from(plan_error);
        let source = error.source().expect("execution-plan source");

        // Then
        assert!(matches!(
            &error,
            ExsiaError::InvalidExecutionPlan(ExecutionPlanError::ZeroK)
        ));
        assert_eq!(source.to_string(), "activation matrix K is zero");
    }
}
