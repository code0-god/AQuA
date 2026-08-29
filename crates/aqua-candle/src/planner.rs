use aqua_runtime::{
    ActivationExecutionPlan, ActivationMatrixShape, ExecutionPlanError, StripePlan,
};
use std::num::NonZeroUsize;

/// Deterministic fixed-row policy used only by the Candle integration bridge.
///
/// This is not a hardware tiler or part of canonical runtime geometry.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct FixedStripePlanner {
    rows_per_stripe: NonZeroUsize,
}

impl FixedStripePlanner {
    pub const fn new(rows_per_stripe: NonZeroUsize) -> Self {
        Self { rows_per_stripe }
    }

    pub const fn rows_per_stripe(self) -> NonZeroUsize {
        self.rows_per_stripe
    }

    pub fn plan(self, shape: &[usize]) -> Result<ActivationExecutionPlan, ExecutionPlanError> {
        let matrix = ActivationMatrixShape::from_tensor_shape(shape)?;
        let rows_per_stripe = self.rows_per_stripe.get();
        let stripes = (0..matrix.rows())
            .step_by(rows_per_stripe)
            .enumerate()
            .map(|(stripe_index, row_start)| {
                let row_end = row_start.saturating_add(rows_per_stripe).min(matrix.rows());
                StripePlan::new(stripe_index, row_start, row_end)
            })
            .collect();

        ActivationExecutionPlan::new(matrix, stripes)
    }
}
