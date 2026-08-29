use std::{error::Error, fmt};

/// Logical activation matrix geometry.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ActivationMatrixShape {
    rows: usize,
    k: usize,
}

impl ActivationMatrixShape {
    /// Interprets a tensor shape as flattened logical rows and a final K axis.
    ///
    /// # Errors
    /// Returns an error when the shape is empty, has a zero-sized matrix
    /// dimension, or its logical element count overflows `usize`.
    pub fn from_tensor_shape(shape: &[usize]) -> Result<Self, ExecutionPlanError> {
        let (&k, leading_dimensions) = shape
            .split_last()
            .ok_or(ExecutionPlanError::EmptyTensorShape)?;

        if k == 0 {
            return Err(ExecutionPlanError::ZeroK);
        }

        let rows = leading_dimensions
            .iter()
            .try_fold(1_usize, |rows, &dimension| {
                rows.checked_mul(dimension)
                    .ok_or(ExecutionPlanError::ElementCountOverflow)
            })?;

        if rows == 0 {
            return Err(ExecutionPlanError::ZeroRows);
        }

        let matrix = Self { rows, k };
        matrix.element_count()?;
        Ok(matrix)
    }

    pub const fn rows(self) -> usize {
        self.rows
    }

    pub const fn k(self) -> usize {
        self.k
    }

    /// Returns the logical activation element count.
    ///
    /// # Errors
    /// Returns `ExecutionPlanError::ElementCountOverflow` when `rows * K`
    /// cannot be represented by `usize`.
    pub fn element_count(self) -> Result<usize, ExecutionPlanError> {
        self.rows
            .checked_mul(self.k)
            .ok_or(ExecutionPlanError::ElementCountOverflow)
    }
}

/// Externally determined half-open row range for one execution stripe.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct StripePlan {
    stripe_index: usize,
    row_start: usize,
    row_end: usize,
}

impl StripePlan {
    pub const fn new(stripe_index: usize, row_start: usize, row_end: usize) -> Self {
        Self {
            stripe_index,
            row_start,
            row_end,
        }
    }

    pub const fn stripe_index(self) -> usize {
        self.stripe_index
    }

    pub const fn row_start(self) -> usize {
        self.row_start
    }

    pub const fn row_end(self) -> usize {
        self.row_end
    }

    pub const fn row_count(self) -> usize {
        self.row_end.saturating_sub(self.row_start)
    }

    pub const fn is_empty(self) -> bool {
        self.row_start >= self.row_end
    }
}

/// Validated stripe execution plan for one logical activation matrix.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ActivationExecutionPlan {
    matrix: ActivationMatrixShape,
    stripes: Vec<StripePlan>,
}

impl ActivationExecutionPlan {
    /// Validates ordered, contiguous stripes covering every logical row.
    ///
    /// # Errors
    /// Returns the first violated stripe-plan invariant.
    pub fn new(
        matrix: ActivationMatrixShape,
        stripes: Vec<StripePlan>,
    ) -> Result<Self, ExecutionPlanError> {
        if stripes.is_empty() {
            return Err(ExecutionPlanError::EmptyStripePlan);
        }

        let mut covered_until = 0;

        for (expected_index, stripe) in stripes.iter().copied().enumerate() {
            if stripe.is_empty() {
                return Err(ExecutionPlanError::EmptyStripe {
                    stripe_index: stripe.stripe_index,
                    row_start: stripe.row_start,
                    row_end: stripe.row_end,
                });
            }

            if stripe.stripe_index != expected_index {
                return Err(ExecutionPlanError::InvalidStripeIndex {
                    expected: expected_index,
                    actual: stripe.stripe_index,
                });
            }

            if stripe.row_end > matrix.rows {
                return Err(ExecutionPlanError::StripeOutOfBounds {
                    stripe_index: stripe.stripe_index,
                    row_end: stripe.row_end,
                    rows: matrix.rows,
                });
            }

            if stripe.row_start > covered_until {
                return Err(ExecutionPlanError::StripeGap {
                    previous_end: covered_until,
                    next_start: stripe.row_start,
                });
            }

            if stripe.row_start < covered_until {
                return Err(ExecutionPlanError::StripeOverlap {
                    previous_end: covered_until,
                    next_start: stripe.row_start,
                });
            }

            covered_until = stripe.row_end;
        }

        if covered_until != matrix.rows {
            return Err(ExecutionPlanError::IncompleteRowCoverage {
                covered_until,
                rows: matrix.rows,
            });
        }

        Ok(Self { matrix, stripes })
    }

    pub const fn matrix(&self) -> ActivationMatrixShape {
        self.matrix
    }

    pub fn stripes(&self) -> &[StripePlan] {
        &self.stripes
    }

    pub fn stripe_count(&self) -> usize {
        self.stripes.len()
    }

    /// Confirms that a tensor has the matrix geometry bound to this plan.
    ///
    /// # Errors
    /// Returns a shape-construction error or `MatrixShapeMismatch`.
    pub fn validate_tensor_shape(&self, shape: &[usize]) -> Result<(), ExecutionPlanError> {
        let actual = ActivationMatrixShape::from_tensor_shape(shape)?;

        if actual == self.matrix {
            return Ok(());
        }

        Err(ExecutionPlanError::MatrixShapeMismatch {
            expected_rows: self.matrix.rows,
            expected_k: self.matrix.k,
            actual_rows: actual.rows,
            actual_k: actual.k,
        })
    }
}

/// Invalid activation geometry or externally supplied stripe plan.
#[derive(Clone, Debug, Eq, PartialEq)]
pub enum ExecutionPlanError {
    EmptyTensorShape,
    ZeroRows,
    ZeroK,
    ElementCountOverflow,
    EmptyStripePlan,
    EmptyStripe {
        stripe_index: usize,
        row_start: usize,
        row_end: usize,
    },
    InvalidStripeIndex {
        expected: usize,
        actual: usize,
    },
    StripeOutOfBounds {
        stripe_index: usize,
        row_end: usize,
        rows: usize,
    },
    StripeGap {
        previous_end: usize,
        next_start: usize,
    },
    StripeOverlap {
        previous_end: usize,
        next_start: usize,
    },
    IncompleteRowCoverage {
        covered_until: usize,
        rows: usize,
    },
    MatrixShapeMismatch {
        expected_rows: usize,
        expected_k: usize,
        actual_rows: usize,
        actual_k: usize,
    },
}

impl fmt::Display for ExecutionPlanError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::EmptyTensorShape => formatter.write_str("activation tensor shape is empty"),
            Self::ZeroRows => formatter.write_str("activation matrix row count is zero"),
            Self::ZeroK => formatter.write_str("activation matrix K is zero"),
            Self::ElementCountOverflow => {
                formatter.write_str("activation matrix element count overflows usize")
            }
            Self::EmptyStripePlan => formatter.write_str("activation stripe plan is empty"),
            Self::EmptyStripe {
                stripe_index,
                row_start,
                row_end,
            } => write!(
                formatter,
                "stripe {stripe_index} has empty row range {row_start}..{row_end}"
            ),
            Self::InvalidStripeIndex { expected, actual } => write!(
                formatter,
                "invalid stripe index: expected {expected}, got {actual}"
            ),
            Self::StripeOutOfBounds {
                stripe_index,
                row_end,
                rows,
            } => write!(
                formatter,
                "stripe {stripe_index} row end {row_end} exceeds matrix rows {rows}"
            ),
            Self::StripeGap {
                previous_end,
                next_start,
            } => write!(
                formatter,
                "stripe row gap between {previous_end} and {next_start}"
            ),
            Self::StripeOverlap {
                previous_end,
                next_start,
            } => write!(
                formatter,
                "stripe row overlap: previous end {previous_end}, next start {next_start}"
            ),
            Self::IncompleteRowCoverage {
                covered_until,
                rows,
            } => write!(
                formatter,
                "stripe plan covers rows through {covered_until}, expected {rows}"
            ),
            Self::MatrixShapeMismatch {
                expected_rows,
                expected_k,
                actual_rows,
                actual_k,
            } => write!(
                formatter,
                "activation matrix shape mismatch: expected rows={expected_rows}, K={expected_k}; got rows={actual_rows}, K={actual_k}"
            ),
        }
    }
}

impl Error for ExecutionPlanError {}

#[cfg(test)]
mod tests;
