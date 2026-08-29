use super::{
    block::{mask_contains, BlockResult},
    math,
};

use crate::{ExsiaConfig, ExsiaError, QuantizedValues, ResidualEvent, ResidualStripe};
use aqua_runtime::{ExecutionPlanError, StripePlan};

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct StripeResult {
    pub(crate) quantized: QuantizedValues,
    pub(crate) exponent: i16,
    pub(crate) theta: i16,
    pub(crate) residual_stripe: ResidualStripe,
}

/// Folds row-major ExSIA blocks into one planned stripe.
///
/// `blocks` must be ordered by local row, then K block. Every full K block
/// has `config.block_size()` values; each row's final block contains only its
/// remaining logical K values.
///
/// # Errors
/// Returns an error when block count, block width, mask width, or checked
/// coordinate arithmetic violates the planned stripe layout.
pub(crate) fn fold_stripe(
    blocks: &[BlockResult],
    config: &ExsiaConfig,
    stripe: StripePlan,
    logical_k: usize,
) -> Result<StripeResult, ExsiaError> {
    debug_assert!(logical_k > 0);

    let block_size = config.block_size();
    let row_count = stripe.row_count();
    let blocks_per_row = logical_k.div_ceil(block_size);
    let expected_block_count = row_count
        .checked_mul(blocks_per_row)
        .ok_or(ExecutionPlanError::ElementCountOverflow)?;

    if blocks.len() != expected_block_count {
        return Err(ExsiaError::InvalidStripeBlockCount {
            stripe_index: stripe.stripe_index(),
            expected: expected_block_count,
            actual: blocks.len(),
        });
    }

    for (local_block_index, block) in blocks.iter().enumerate() {
        let block_in_row = local_block_index % blocks_per_row;
        let k_start = block_in_row
            .checked_mul(block_size)
            .ok_or(ExecutionPlanError::ElementCountOverflow)?;
        let expected_width = (logical_k - k_start).min(block_size);

        if block.wide.len() != expected_width {
            return Err(ExsiaError::InvalidStripeBlockWidth {
                stripe_index: stripe.stripe_index(),
                local_block_index,
                expected: expected_width,
                actual: block.wide.len(),
            });
        }

        let valid_mask = if expected_width == u32::BITS as usize {
            u32::MAX
        } else {
            (1_u32 << expected_width) - 1
        };

        if block.outlier_mask & !valid_mask != 0 {
            return Err(ExsiaError::InvalidStripeBlockMask {
                stripe_index: stripe.stripe_index(),
                local_block_index,
                valid_element_count: expected_width,
                mask: block.outlier_mask,
            });
        }
    }

    let mut e1 = math::NEG_INF_EXP;
    let mut e2 = math::NEG_INF_EXP;

    for block in blocks {
        let exponent = block.exponent;
        if exponent > e1 {
            e2 = e1;
            e1 = exponent;
        } else if exponent < e1 && exponent > e2 {
            e2 = exponent;
        }
    }

    let (stripe_exponent, promote_top_block) = if e1 == math::NEG_INF_EXP {
        (0, false)
    } else if e2 == math::NEG_INF_EXP {
        (e1, false)
    } else {
        (e2, true)
    };

    let stripe_theta = math::exp_to_theta(stripe_exponent, config.rho());
    let element_count = row_count
        .checked_mul(logical_k)
        .ok_or(ExecutionPlanError::ElementCountOverflow)?;
    let mut quantized = QuantizedValues::with_capacity(config.precision, element_count);
    let mut residual_stripe = ResidualStripe::with_capacity(
        stripe.stripe_index(),
        stripe.row_start(),
        row_count,
        logical_k,
        0,
    );

    for (local_block_index, block) in blocks.iter().enumerate() {
        let local_row = local_block_index / blocks_per_row;
        let block_in_row = local_block_index % blocks_per_row;
        let k_start = block_in_row
            .checked_mul(block_size)
            .ok_or(ExecutionPlanError::ElementCountOverflow)?;
        let delta = if block.exponent == math::NEG_INF_EXP {
            0
        } else {
            block.exponent - stripe_exponent
        };
        let promote_block = promote_top_block && block.exponent == e1;

        for (element_index, &wide) in block.wide.iter().enumerate() {
            let shifted = math::shift_i32(wide, delta);
            let (clipped, residual) =
                math::clip_with_residual(shifted, config.qmin(), config.qmax());
            quantized.push_clipped(clipped);

            let outlier = promote_block || mask_contains(block.outlier_mask, element_index);

            if outlier && residual != 0 {
                let k = k_start
                    .checked_add(element_index)
                    .ok_or(ExecutionPlanError::ElementCountOverflow)?;
                debug_assert!(k < logical_k);
                residual_stripe.push(ResidualEvent::new(local_row, k, residual));
            }
        }
    }

    Ok(StripeResult {
        quantized,
        exponent: stripe_exponent,
        theta: stripe_theta,
        residual_stripe,
    })
}

#[cfg(test)]
#[path = "stripe/contract_tests.rs"]
mod tests;
