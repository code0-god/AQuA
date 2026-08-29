use super::math::{self, SigmaStats};

use crate::{ExsiaConfig, ExsiaError, EXSIA_BLOCK_SIZE};

#[derive(Clone, Debug, Eq, PartialEq)]
pub(crate) struct BlockResult {
    pub(crate) wide: Vec<i32>, // 최종 block scale에서 표현된 wide integer activation.
    pub(crate) exponent: i16,  // 최종 block exponent e_b.
    pub(crate) outlier_mask: u32, // 선택된 outlier 위치. bit i = element i.
}

pub(crate) fn mask_set(mask: &mut u32, index: usize) {
    debug_assert!(index < EXSIA_BLOCK_SIZE);

    *mask |= 1_u32 << index; // index 위치의 bit를 1로 설정.
}

pub(crate) fn mask_contains(mask: u32, index: usize) -> bool {
    debug_assert!(index < EXSIA_BLOCK_SIZE);

    mask & (1_u32 << index) != 0 // index 위치의 bit가 설정되어 있는지 확인.
}

pub(crate) fn quantize_block(
    values: &[f32],
    config: &ExsiaConfig,
) -> Result<BlockResult, ExsiaError> {
    if values.is_empty()
        || config.block_size == 0
        || config.block_size > EXSIA_BLOCK_SIZE
        || values.len() > config.block_size
    {
        return Err(ExsiaError::InvalidBlockLength {
            len: values.len(),
            block_size: config.block_size,
        });
    }

    /*
     * Step 1
     *
     * 각 activation의 unbiased exponent를 계산하고,
     * 가장 큰 두 개의 distinct exponent e1, e2를 찾는다.
     *
     * e1 bucket은 preliminary outlier로 선택한다.
     *
     * 단, block에 distinct exponent bucket이 하나뿐이면
     * 해당 bucket을 outlier로 제거하지 않는다.
     */

    let mut e1 = math::NEG_INF_EXP; // 가장 큰 exponent.
    let mut e2 = math::NEG_INF_EXP; // 두 번째로 큰 distinct exponent.

    let mut outlier_mask = 0_u32;

    // 이후 integer outlier 제거 후 final exponent를 찾을 때
    // 다시 FP exponent를 계산하지 않도록 저장.
    let mut exponents = [math::NEG_INF_EXP; EXSIA_BLOCK_SIZE];

    for (i, &value) in values.iter().enumerate() {
        let exp = math::unbiased_exp(value);

        exponents[i] = exp;

        if exp > e1 {
            // 새로운 최대 exponent가 나타났으므로 기존 e1을 e2로 이동.
            e2 = e1;
            e1 = exp;

            // top exponent bucket 자체가 바뀌었으므로 이전 preliminary mask는 폐기.
            outlier_mask = 0;

            if exp != math::NEG_INF_EXP {
                mask_set(&mut outlier_mask, i);
            }
        } else if exp == e1 && exp != math::NEG_INF_EXP {
            // 동일한 top exponent를 가지는 모든 element를 같은 preliminary outlier bucket으로 선택.
            mask_set(&mut outlier_mask, i);
        } else if exp < e1 && exp > e2 {
            // e1보다 작고 현재 e2보다 큰 exponent이면 새로운 두 번째 distinct exponent.
            e2 = exp;
        }
    }

    let has_second_bucket = e2 != math::NEG_INF_EXP;

    if !has_second_bucket {
        // distinct exponent가 하나뿐이면 top bucket을 outlier로 분리하지 않는다.
        outlier_mask = 0;
    }

    let e_pre = if has_second_bucket {
        e2 // top bucket을 제외한 두 번째 exponent를 provisional scale로 사용.
    } else {
        e1 // 하나의 bucket만 있으면 해당 exponent 자체를 사용.
    };

    /*
     * Step 2
     *
     * provisional exponent e_pre에서 wide i32 quantization을 수행한다.
     * preliminary outlier mask에 포함되지 않은 값만 사용하여
     *
     *   S1  = Σ |q|
     *   S2 = Σ |q|²
     *   N  = unmasked element count
     *
     * 를 계산한다.
     */

    let theta_pre = math::exp_to_theta(e_pre, config.rho());
    let mut wide = Vec::with_capacity(values.len());

    let mut stats = SigmaStats {
        sum: 0,
        sum_sq: 0,
        n: 0,
    };

    for (i, &value) in values.iter().enumerate() {
        let q = math::quantize_i32(value, theta_pre);

        wide.push(q);

        if mask_contains(outlier_mask, i) {
            continue;
        }

        // q를 먼저 i128로 넓힌 뒤 제곱해야 한다.
        // q * q를 i32에서 먼저 계산하면 overflow 가능.
        let magnitude = i128::from(math::magnitude_i32(q));

        stats.sum += magnitude;
        stats.sum_sq += magnitude * magnitude;
        stats.n += 1;
    }

    /*
     * Step 3
     *
     * provisional integer representation에서 sigma outlier를 탐지한다.
     * preliminary top-exponent outlier는 이미 mask되어 있으므로 sigma statistics와 detection 대상에서 제외한다.
     *
     * sigma outlier가 아닌 element 중 가장 큰 exponent를 final_exp로 추적한다.
     */

    let mut has_integer_outlier = false;
    let mut final_exp = math::NEG_INF_EXP;

    for (i, &q) in wide.iter().enumerate() {
        if mask_contains(outlier_mask, i) {
            continue;
        }

        if math::is_sigma_outlier(q, &stats, config.sigma()) {
            // integer-domain sigma detector가 선택한 element를
            // 최종 outlier mask에 추가.
            mask_set(&mut outlier_mask, i);

            has_integer_outlier = true;
        } else {
            // outlier가 아닌 element 중 가장 큰 exponent가
            // 새로운 block exponent 후보가 됨.
            final_exp = final_exp.max(exponents[i]);
        }
    }

    /*
     * Step 4
     *
     * integer outlier가 하나도 추가되지 않았다면
     * provisional exponent e_pre를 그대로 사용한다.
     *
     * integer outlier가 추가되었다면 mask 이후 남은 element의
     * 가장 큰 exponent를 최종 block exponent로 사용한다.
     */

    let block_exp = if has_integer_outlier {
        final_exp
    } else {
        e_pre
    };

    let theta_final = math::exp_to_theta(block_exp, config.rho());

    /*
     * provisional scale과 final scale이 같으면
     * Step 2에서 계산한 quantized 값을 그대로 재사용한다.
     *
     * scale이 실제로 변경된 경우에만 block 전체를 다시 quantize한다.
     * 이것이 ExSIA의 local requantization avoidance 경로다.
     */

    if has_integer_outlier && theta_final != theta_pre {
        for (quantized, &value) in wide.iter_mut().zip(values) {
            *quantized = math::quantize_i32(value, theta_final);
        }
    }

    Ok(BlockResult {
        wide,
        exponent: block_exp,
        outlier_mask,
    })
}

#[cfg(test)]
mod tests {
    use super::{mask_contains, quantize_block};

    use crate::{ExsiaConfig, ExsiaError, ExsiaPrecision, EXSIA_BLOCK_SIZE};

    #[test]
    fn selects_top_exponent_bucket_as_preliminary_outlier() {
        let mut values = vec![1.0; EXSIA_BLOCK_SIZE];

        values[0] = 8.0; // exponent 3. 나머지는 exponent 0.

        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = quantize_block(&values, &config).expect("valid block");

        // top exponent bucket의 element가 preliminary outlier.
        assert!(mask_contains(result.outlier_mask, 0));

        // second exponent bucket은 e=0.
        assert_eq!(result.exponent, 0);

        // I8 rho=6, theta=0-6=-6.
        // 1.0 × 2^6 = 64.
        assert_eq!(result.wide[1], 64);
    }

    #[test]
    fn clears_preliminary_mask_when_only_one_exponent_bucket_exists() {
        let values = [1.0_f32, 1.5];

        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = quantize_block(&values, &config).expect("valid block");

        // 두 값 모두 exponent 0이므로 distinct exponent bucket은 하나뿐.
        // 따라서 preliminary top bucket mask는 사용하지 않음.
        assert_eq!(result.outlier_mask, 0);

        assert_eq!(result.exponent, 0);
    }

    #[test]
    fn detects_integer_sigma_outlier() {
        let values = [8.0, 1.99, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0];

        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = quantize_block(&values, &config).expect("valid block");

        // 8.0은 exponent top bucket.
        assert!(mask_contains(result.outlier_mask, 0));

        // 1.99는 같은 exponent bucket의 1.0 값들에 비해
        // integer magnitude가 충분히 커서 2σ outlier가 됨.
        assert!(mask_contains(result.outlier_mask, 1));

        // 1.0 값들은 outlier가 아님.
        assert!(!mask_contains(result.outlier_mask, 2));
    }

    #[test]
    fn requantizes_when_integer_outlier_changes_block_scale() {
        let values = [8.0, 3.875, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0];

        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = quantize_block(&values, &config).expect("valid block");

        // 8.0 exponent = 3 -> preliminary top bucket.
        assert!(mask_contains(result.outlier_mask, 0));

        // 3.875 exponent = 1이지만 integer sigma outlier가 됨.
        assert!(mask_contains(result.outlier_mask, 1));

        // 두 outlier를 제외한 나머지 1.0의 exponent는 0.
        assert_eq!(result.exponent, 0);

        // final theta = 0 - rho(6) = -6.
        // 따라서 1.0은 최종적으로 64가 되어야 함.
        assert_eq!(result.wide[2], 64);
    }

    #[test]
    fn accepts_partial_block() {
        let values = vec![1.0; 17];

        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        let result = quantize_block(&values, &config).expect("partial block is valid");

        // Rust reference에서는 logical element만 반환하고,
        // hardware padding은 이후 BSV execution contract에서 처리.
        assert_eq!(result.wide.len(), 17);
    }

    #[test]
    fn rejects_empty_block() {
        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        assert!(matches!(
            quantize_block(&[], &config),
            Err(ExsiaError::InvalidBlockLength {
                len: 0,
                block_size: EXSIA_BLOCK_SIZE,
            })
        ));
    }

    #[test]
    fn rejects_block_larger_than_configured_size() {
        let values = vec![1.0; EXSIA_BLOCK_SIZE + 1];

        let config = ExsiaConfig::new(ExsiaPrecision::I8);

        assert!(matches!(
            quantize_block(&values, &config),
            Err(ExsiaError::InvalidBlockLength {
                len,
                block_size: EXSIA_BLOCK_SIZE,
            }) if len == EXSIA_BLOCK_SIZE + 1
        ));
    }
}
