use crate::{
    algorithm::{block::quantize_block, math, stripe::fold_stripe},
    ExsiaError, ExsiaInput, ExsiaOutput, QuantizedValues,
};
use aqua_runtime::ActivationExecutionPlan;

/// Canonical AQuA ExSIA reference.
///
/// This implementation defines the software semantics that the future BSV
/// datapath must reproduce. Earlier software implementations are used as
/// algorithmic references, but AQuA may intentionally define clearer
/// hardware-oriented semantics such as flush-to-zero handling for subnormal
/// activations.
#[derive(Clone, Copy, Debug, Default)]
pub struct ReferenceExsia;

impl ReferenceExsia {
    pub const fn new() -> Self {
        Self
    }

    pub fn execute(
        &self,
        input: &ExsiaInput<'_>,
        plan: &ActivationExecutionPlan,
    ) -> Result<ExsiaOutput, ExsiaError> {
        plan.validate_tensor_shape(input.shape())?;

        let matrix = plan.matrix();
        let rows = matrix.rows();
        let logical_k = matrix.k();
        let config = input.config();
        let block_size = config.block_size();
        let blocks_per_row = logical_k.div_ceil(block_size);
        let values = input.values();

        let mut quantized = QuantizedValues::with_capacity(config.precision, input.len());
        let mut stripe_theta = Vec::with_capacity(plan.stripe_count());
        let mut residual_stripes = Vec::with_capacity(plan.stripe_count());

        for &stripe in plan.stripes() {
            let mut stripe_result = {
                let stripe_block_count = stripe.row_count() * blocks_per_row;
                let mut blocks = Vec::with_capacity(stripe_block_count);

                for row in stripe.row_start()..stripe.row_end() {
                    let row_base = row * logical_k;

                    for block_in_row in 0..blocks_per_row {
                        let k_start = block_in_row * block_size;
                        let k_end = k_start.saturating_add(block_size).min(logical_k);
                        let start = row_base + k_start;
                        let end = row_base + k_end;

                        blocks.push(quantize_block(&values[start..end], &config)?);
                    }
                }

                fold_stripe(&blocks, &config, stripe, logical_k)?
            };

            debug_assert_eq!(
                stripe_result.theta,
                math::exp_to_theta(stripe_result.exponent, config.rho())
            );
            quantized.append(&mut stripe_result.quantized);
            stripe_theta.push(stripe_result.theta);
            residual_stripes.push(stripe_result.residual_stripe);
        }

        debug_assert_eq!(rows * logical_k, input.len());
        debug_assert_eq!(quantized.len(), input.len());
        debug_assert_eq!(stripe_theta.len(), plan.stripe_count());
        debug_assert_eq!(residual_stripes.len(), plan.stripe_count());

        for (residual, stripe) in residual_stripes.iter().zip(plan.stripes()) {
            debug_assert_eq!(residual.stripe_index(), stripe.stripe_index());
            debug_assert_eq!(residual.row_start(), stripe.row_start());
            debug_assert_eq!(residual.row_count(), stripe.row_count());
            debug_assert_eq!(residual.logical_k(), logical_k);
        }

        Ok(ExsiaOutput {
            quantized,
            stripe_theta,
            residual_stripes,
            shape: input.shape().to_vec(),
        })
    }
}

#[cfg(test)]
#[path = "reference/contract_tests.rs"]
mod tests;
