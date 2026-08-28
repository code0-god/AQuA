use super::{
    block::{mask_contains, BlockResult},
    math,
};

use crate::{ExsiaConfig, QuantizedValues, ResidualEntry, Residuals};

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct StripeResult {
    pub(crate) quantized: QuantizedValues,
    pub(crate) exponent: i16,
    pub(crate) theta: i16,
    pub(crate) residuals: Residuals,
}

pub(crate) fn fold_stripe(
    blocks: &[BlockResult],
    config: &ExsiaConfig,
    first_block_index: usize,
) -> StripeResult {
    debug_assert!(!blocks.is_empty());

    // step 1
    let mut e1 = math::NEG_INF_EXP;
    let mut e2 = math::NEG_INF_EXP;

    for blk in blocks {
        let exp = blk.exponent;
        if exp > e1 {
            e2 = e1;
            e1 = exp;
        } else if exp < e1 && exp > e2 {
            e2 = exp;
        }
    }

    // step 2
    let (stripe_exp, promote_top_block) = if e1 == math::NEG_INF_EXP {
        (0, false)
    } else if e2 == math::NEG_INF_EXP {
        (e1, false)
    } else {
        (e2, true)
    };

    let stripe_theta = math::exp_to_theta(stripe_exp, config.rho());
    let element_count: usize = blocks.iter().map(|block| block.wide.len()).sum();
    let mut quantized = QuantizedValues::with_capacity(config.precision, element_count);
    let mut residuals = Residuals::new();

    // step 3
    for (local_block_index, block) in blocks.iter().enumerate() {
        let delta = if block.exponent == math::NEG_INF_EXP {
            0
        } else {
            block.exponent - stripe_exp
        };

        /*
         * stripe에 두 개 이상의 distinct block exponent가 있을 때,
         * e1을 사용하는 block 전체는 stripe-level outlier block으로
         * 승격한다.
         *
         * 따라서 block-level mask에 없던 inlier도 최종 outlier가 된다.
         */

        let promote_block = promote_top_block && block.exponent == e1;

        for (element_index, &q) in block.wide.iter().enumerate() {
            let shifted = math::shift_i32(q, delta);

            let (clipped, residual) =
                math::clip_with_residual(shifted, config.qmin(), config.qmax());

            // clipping이 끝났으므로 여기부터 실제 target precision.
            quantized.push_clipped(clipped);

            /*
             * 최종 outlier는:
             *
             * 1. block-level ExSIA가 선택한 outlier
             * 2. stripe folding에서 e1 block 전체가 승격된 경우
             *
             * 둘 중 하나라도 만족하면 true.
             */

            let outlier = promote_block || mask_contains(block.outlier_mask, element_index);

            /*
             * 실제 clipping residual이 존재하는 최종 outlier만
             * sparse residual list에 저장.
             */

            if outlier && residual != 0 {
                residuals.push(ResidualEntry::new(
                    first_block_index + local_block_index,
                    element_index,
                    residual,
                ));
            }
        }
    }

    StripeResult {
        quantized,
        exponent: stripe_exp,
        theta: stripe_theta,
        residuals,
    }
}

#[cfg(test)]
mod tests {
    use super::{
        super::{block::BlockResult, math},
        fold_stripe,
    };

    use crate::{ExsiaConfig, ExsiaPrecision, QuantizedValues, ResidualEntry};

    fn block(wide: Vec<i32>, exponent: i16, outlier_mask: u32) -> BlockResult {
        BlockResult {
            wide,
            exponent,
            outlier_mask,
        }
    }

    #[test]
    fn folds_single_exponent_without_promotion() {
        let blocks = [block(vec![20], 1, 0), block(vec![30], 1, 0)];
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = fold_stripe(&blocks, &config, 0);

        assert_eq!(result.quantized, QuantizedValues::I8(vec![20, 30]));
        assert_eq!(result.exponent, 1);
        assert_eq!(result.theta, 1 - config.rho());
        assert!(result.residuals.is_empty());
    }

    #[test]
    fn uses_second_distinct_exponent_for_stripe_scale() {
        let blocks = [block(vec![10], 3, 0), block(vec![10], 1, 0)];
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = fold_stripe(&blocks, &config, 0);

        assert_eq!(result.quantized, QuantizedValues::I8(vec![40, 10]));
        assert_eq!(result.exponent, 1);
        assert_eq!(result.theta, -5);
        assert!(result.residuals.is_empty());
    }

    #[test]
    fn promotes_top_exponent_block_for_residual_capture() {
        let blocks = [block(vec![100], 3, 0), block(vec![10], 1, 0)];
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = fold_stripe(&blocks, &config, 0);

        assert_eq!(result.quantized, QuantizedValues::I8(vec![127, 10]));
        assert_eq!(result.exponent, 1);
        assert_eq!(result.residuals.entries(), &[ResidualEntry::new(0, 0, 273)]);
    }

    #[test]
    fn captures_existing_block_outlier_residual() {
        let blocks = [block(vec![200], 1, 1_u32)];
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = fold_stripe(&blocks, &config, 0);

        assert_eq!(result.quantized, QuantizedValues::I8(vec![127]));
        assert_eq!(result.residuals.entries(), &[ResidualEntry::new(0, 0, 73)]);
    }

    #[test]
    fn omits_selected_outlier_without_clipping_residual() {
        let blocks = [block(vec![10], 1, 1_u32)];
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = fold_stripe(&blocks, &config, 0);

        assert_eq!(result.quantized, QuantizedValues::I8(vec![10]));
        assert!(result.residuals.is_empty());
    }

    #[test]
    fn folds_all_invalid_zero_blocks_at_zero_exponent() {
        let blocks = [
            block(vec![0, 0], math::NEG_INF_EXP, 0),
            block(vec![0], math::NEG_INF_EXP, 0),
        ];
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = fold_stripe(&blocks, &config, 0);

        assert_eq!(result.quantized, QuantizedValues::I8(vec![0, 0, 0]));
        assert_eq!(result.exponent, 0);
        assert_eq!(result.theta, -config.rho());
        assert!(result.residuals.is_empty());
    }

    #[test]
    fn clips_i4_after_scale_alignment() {
        let blocks = [block(vec![6], 1, 0), block(vec![2], 0, 0)];
        let config = ExsiaConfig::new(ExsiaPrecision::I4);

        let result = fold_stripe(&blocks, &config, 0);

        assert_eq!(result.quantized, QuantizedValues::I4(vec![7, 2]));
        assert_eq!(result.exponent, 0);
        assert_eq!(result.residuals.entries(), &[ResidualEntry::new(0, 0, 5)]);
    }

    #[test]
    fn produces_i8_quantized_values() {
        let blocks = [block(vec![-128, 0, 127], 0, 0)];
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = fold_stripe(&blocks, &config, 0);

        assert_eq!(result.quantized, QuantizedValues::I8(vec![-128, 0, 127]));
    }

    #[test]
    fn produces_i16_quantized_values_without_clipping() {
        let blocks = [block(vec![-32_000, 0, 30_000], 0, 0)];
        let config = ExsiaConfig::new(ExsiaPrecision::I16);

        let result = fold_stripe(&blocks, &config, 0);

        assert_eq!(
            result.quantized,
            QuantizedValues::I16(vec![-32_000, 0, 30_000])
        );
        assert!(result.residuals.is_empty());
    }

    #[test]
    fn offsets_residual_block_indices() {
        let blocks = [block(vec![200], 1, 1_u32), block(vec![-200], 1, 1_u32)];
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = fold_stripe(&blocks, &config, 7);

        assert_eq!(
            result.residuals.entries(),
            &[ResidualEntry::new(7, 0, 73), ResidualEntry::new(8, 0, -72),]
        );
    }

    #[test]
    fn preserves_logical_element_order() {
        let blocks = [
            block(vec![1, 2], 0, 0),
            block(vec![3, 4], 0, 0),
            block(vec![5], 0, 0),
        ];
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = fold_stripe(&blocks, &config, 0);

        assert_eq!(result.quantized, QuantizedValues::I8(vec![1, 2, 3, 4, 5]));
    }
}
