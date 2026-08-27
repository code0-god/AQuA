pub(crate) const NEG_INF_EXP: i16 = i16::MIN; // 유효한 exponent가 없음을 나타내는 sentinel.

pub(crate) fn unbiased_exp(x: f32) -> i16 {
    if x == 0.0 || x.is_subnormal() || !x.is_finite() {
        // AQuA는 zero, subnormal, NaN, ±Inf를 유효한 activation exponent로 취급하지 않음.
        // 특히 IEEE-754 subnormal은 hardware 단순화를 위해 flush-to-zero 처리.
        return NEG_INF_EXP;
    }

    let bits = x.abs().to_bits(); // 부호를 제거한 f32의 IEEE-754 bit pattern을 u32로 변환.
    let biased_exp = ((bits >> 23) & 0xff) as i16; // bits[30:23]의 exponent field 추출.

    // 여기까지 왔다면 x는 normal finite f32이므로 exponent field는 1..=254.
    biased_exp - 127 // IEEE-754 binary32 exponent bias 127을 제거하여 unbiased exponent 반환.
}

pub(crate) fn exp_to_theta(exp: i16, rho: i16) -> i16 {
    if exp == NEG_INF_EXP {
        // 유효한 exponent가 없으면 quantization scale exponent도 유효하지 않음.
        NEG_INF_EXP
    } else {
        exp - rho // θ = e - ρ.
    }
}

pub(crate) fn quantize_i32(x: f32, theta: i16) -> i32 {
    if theta == NEG_INF_EXP || x == 0.0 || x.is_subnormal() || !x.is_finite() {
        // 유효하지 않은 scale 또는 zero/subnormal/NaN/±Inf는 quantize하지 않음.
        // unbiased_exp()와 동일하게 subnormal을 flush-to-zero 처리.
        return 0;
    }

    // C++의 std::ldexp(static_cast<double>(x), -theta)와 같은 의도.
    let scaled = f64::from(x) // f32 -> f64 변환. scaling 계산의 중간 precision을 확보.
        * 2.0_f64.powi(-i32::from(theta)); // x × 2^(-theta) = x / 2^theta.

    if !scaled.is_finite() {
        // scaling 결과가 ±Inf가 될 정도로 커진 경우 i32 범위로 saturation.
        return if scaled.is_sign_negative() {
            i32::MIN // 음의 overflow는 i32 최솟값으로 saturation.
        } else {
            i32::MAX // 양의 overflow는 i32 최댓값으로 saturation.
        };
    }

    if scaled <= f64::from(i32::MIN) {
        // i32가 표현 가능한 최소값 이하이면 i32::MIN으로 saturation.
        return i32::MIN;
    }

    if scaled >= f64::from(i32::MAX) {
        // i32가 표현 가능한 최대값 이상이면 i32::MAX로 saturation.
        return i32::MAX;
    }

    // AQuA wide quantization은 ties-to-even 반올림을 canonical semantics로 사용.
    scaled.round_ties_even() as i32 // 반올림 후 i32 wide quantized value 반환.
}

pub(crate) fn magnitude_i32(value: i32) -> i64 {
    let widened = i64::from(value); // i32::MIN의 절댓값도 표현할 수 있도록 먼저 i64로 확장.

    if widened < 0 {
        -widened // 음수이면 부호를 반전하여 magnitude 반환.
    } else {
        widened // 이미 양수이면 그대로 반환.
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) struct SigmaStats {
    pub sum: i128,    // S = Σ|q|.
    pub sum_sq: i128, // SS = Σ|q|².
    pub n: usize,     // 통계에 포함된 unmasked element 개수.
}

pub(crate) fn is_sigma_outlier(
    q: i32,
    stats: &SigmaStats, // 통계값을 소유하지 않고 immutable borrow.
    sigma: i32,
) -> bool {
    debug_assert!(sigma > 0); // debug build에서 sigma가 양수인지 확인.

    if stats.n == 0 {
        return false; // sample이 없으면 outlier 판정 불가.
    }

    let n = stats.n as i128; // 이후 S/SS와 동일한 i128 domain에서 계산.

    let variance_numer = n * stats.sum_sq - stats.sum * stats.sum;
    // N·SS - S² = N²·variance.
    // division과 sqrt 없이 sigma condition을 계산하기 위한 variance numerator.

    if variance_numer <= 0 {
        return false; // variance가 0 이하이면 sigma outlier가 존재할 수 없음.
    }

    let centered = n * i128::from(magnitude_i32(q)) - stats.sum;
    // N|q| - S = N(|q| - μ).
    // 현재 |q|가 평균보다 얼마나 큰지를 division 없이 표현.

    if centered <= 0 {
        return false; // 평균 이하의 magnitude는 upper-tail outlier가 아님.
    }

    let sigma = i128::from(sigma); // 아래 모든 계산을 i128 domain에서 수행.
    let threshold = sigma * sigma * variance_numer; // σ²(N·SS - S²).

    centered * centered > threshold
    // (N|q| - S)² > σ²(N·SS - S²).
    // strict `>`이므로 정확히 경계값에 있는 element는 outlier가 아님.
}

fn round_shift_right_i32(q: i32, shift: u32) -> i32 {
    debug_assert!(shift <= 31); // shift_i32()가 right shift를 최대 31bit로 제한.

    if shift == 0 {
        return q; // shift가 없으면 입력 그대로 반환.
    }

    let x = i64::from(q); // offset addition과 i32::MIN 처리를 위해 i64로 확장.
    let offset = 1_i64 << (shift - 1); // 2^(shift-1): nearest rounding을 위한 절반 offset.

    if x >= 0 {
        ((x + offset) >> shift) as i32
        // 양수: offset을 더한 뒤 right shift하여 nearest integer로 반올림.
    } else {
        -(((-x + offset) >> shift) as i32)
        // 음수: magnitude에 동일한 rounding을 적용한 후 부호 복원.
        // half-way에서는 0에서 멀어지는 방향으로 반올림.
    }
}

pub(crate) fn shift_i32(q: i32, delta: i16) -> i32 {
    if delta > 0 {
        // delta > 0이면 block scale보다 stripe scale이 더 작으므로
        // q × 2^delta 형태의 left shift가 필요.

        let shift = i32::from(delta).min(31) as u32; // i32 shift 범위에 맞춰 최대 31bit.
        let negative = q < 0; // saturation 후 원래 부호를 복원하기 위해 저장.

        let magnitude = if negative {
            (-i64::from(q)) as u64
            // i32::MIN도 안전하게 magnitude로 표현하기 위해 i64에서 negate 후 u64 변환.
        } else {
            q as u64
        };

        let shifted = magnitude << shift; // unsigned magnitude를 left shift.

        if !negative {
            if shifted > i32::MAX as u64 {
                i32::MAX // positive overflow는 i32::MAX로 saturation.
            } else {
                shifted as i32 // 범위 안이면 그대로 i32로 복원.
            }
        } else {
            let negative_limit = 1_u64 << 31; // |-i32::MIN| = 2^31.

            if shifted >= negative_limit {
                i32::MIN // 음수 magnitude가 2^31 이상이면 i32::MIN으로 saturation.
            } else {
                -(shifted as i32) // 범위 안이면 음수 부호를 복원.
            }
        }
    } else if delta < 0 {
        // delta < 0이면 q / 2^|delta|가 필요하므로 rounded right shift 수행.

        let shift = (-i32::from(delta)).min(31) as u32; // 절댓값을 구한 뒤 최대 31bit 제한.

        round_shift_right_i32(q, shift) // signed nearest rounding을 적용한 right shift.
    } else {
        q // delta == 0이면 scale 변환이 필요하지 않음.
    }
}

pub(crate) fn clip_with_residual(q: i32, qmin: i32, qmax: i32) -> (i32, i32) {
    debug_assert!(qmin <= qmax); // 올바른 quantization 범위인지 확인.
    debug_assert!(qmin <= 0); // AQuA signed quantization range는 0 이하의 minimum을 가짐.
    debug_assert!(qmax >= 0); // AQuA signed quantization range는 0 이상의 maximum을 가짐.

    let clipped = if q > qmax {
        qmax // upper bound를 넘으면 qmax로 clipping.
    } else if q < qmin {
        qmin // lower bound보다 작으면 qmin으로 clipping.
    } else {
        q // 범위 안이면 원래 값 유지.
    };

    (clipped, q - clipped)
    // residual = original wide value - clipped value.
    // 따라서 항상 q = clipped + residual 관계가 유지됨.
}

#[cfg(test)]
mod tests {
    use super::{
        clip_with_residual, exp_to_theta, is_sigma_outlier, magnitude_i32, quantize_i32, shift_i32,
        unbiased_exp, SigmaStats, NEG_INF_EXP,
    };

    #[test]
    fn unbiased_exp_returns_expected_normal_exponents() {
        assert_eq!(unbiased_exp(1.0), 0); // 1.0 = 1 × 2^0.
        assert_eq!(unbiased_exp(2.0), 1); // 2.0 = 1 × 2^1.
        assert_eq!(unbiased_exp(0.5), -1); // 0.5 = 1 × 2^-1.
        assert_eq!(unbiased_exp(3.5), 1); // 3.5 = 1.75 × 2^1.
        assert_eq!(unbiased_exp(-8.0), 3); // 부호와 무관하게 |x|의 exponent 사용.
        assert_eq!(unbiased_exp(f32::MIN_POSITIVE), -126); // 가장 작은 normal f32.
    }

    #[test]
    fn unbiased_exp_rejects_zero_and_non_finite_values() {
        assert_eq!(unbiased_exp(0.0), NEG_INF_EXP);
        assert_eq!(unbiased_exp(-0.0), NEG_INF_EXP);
        assert_eq!(unbiased_exp(f32::INFINITY), NEG_INF_EXP);
        assert_eq!(unbiased_exp(f32::NEG_INFINITY), NEG_INF_EXP);
        assert_eq!(unbiased_exp(f32::NAN), NEG_INF_EXP);
    }

    #[test]
    fn unbiased_exp_flushes_subnormal_values_to_zero() {
        let smallest_subnormal = f32::from_bits(0x0000_0001);
        let largest_subnormal = f32::from_bits(0x007f_ffff);

        assert!(smallest_subnormal.is_subnormal());
        assert!(largest_subnormal.is_subnormal());

        assert_eq!(unbiased_exp(smallest_subnormal), NEG_INF_EXP);
        assert_eq!(unbiased_exp(largest_subnormal), NEG_INF_EXP);
    }

    #[test]
    fn exp_to_theta_applies_rho() {
        assert_eq!(exp_to_theta(4, 6), -2);
        assert_eq!(exp_to_theta(-3, 6), -9);
    }

    #[test]
    fn exp_to_theta_preserves_invalid_exponent() {
        assert_eq!(exp_to_theta(NEG_INF_EXP, 6), NEG_INF_EXP);
    }

    #[test]
    fn quantize_i32_scales_by_power_of_two() {
        assert_eq!(quantize_i32(3.0, -2), 12); // 3.0 × 2^2 = 12.
        assert_eq!(quantize_i32(8.0, 1), 4); // 8.0 × 2^-1 = 4.
        assert_eq!(quantize_i32(-3.0, -1), -6); // -3.0 × 2^1 = -6.
    }

    #[test]
    fn quantize_i32_uses_ties_to_even() {
        assert_eq!(quantize_i32(2.5, 0), 2);
        assert_eq!(quantize_i32(3.5, 0), 4);
        assert_eq!(quantize_i32(-2.5, 0), -2);
        assert_eq!(quantize_i32(-3.5, 0), -4);
    }

    #[test]
    fn quantize_i32_rejects_invalid_values() {
        assert_eq!(quantize_i32(1.0, NEG_INF_EXP), 0);
        assert_eq!(quantize_i32(f32::NAN, 0), 0);
        assert_eq!(quantize_i32(f32::INFINITY, 0), 0);
        assert_eq!(quantize_i32(f32::NEG_INFINITY, 0), 0);
    }

    #[test]
    fn quantize_i32_flushes_subnormal_values_to_zero() {
        let subnormal = f32::from_bits(0x0000_0001);

        assert!(subnormal.is_subnormal());
        assert_eq!(quantize_i32(subnormal, -100), 0);
    }

    #[test]
    fn quantize_i32_keeps_zero_zero_for_extreme_scale() {
        // 매우 큰 2^(-theta)가 생기더라도 0 × Inf가 NaN으로 전파되지 않아야 함.
        assert_eq!(quantize_i32(0.0, i16::MAX), 0);
        assert_eq!(quantize_i32(0.0, i16::MIN + 1), 0);
    }

    #[test]
    fn quantize_i32_saturates_to_i32_range() {
        assert_eq!(quantize_i32(f32::MAX, -100), i32::MAX);
        assert_eq!(quantize_i32(-f32::MAX, -100), i32::MIN);
    }

    #[test]
    fn magnitude_i32_handles_positive_and_negative_values() {
        assert_eq!(magnitude_i32(0), 0);
        assert_eq!(magnitude_i32(7), 7);
        assert_eq!(magnitude_i32(-7), 7);
    }

    #[test]
    fn magnitude_i32_handles_i32_min() {
        assert_eq!(magnitude_i32(i32::MIN), 2_147_483_648_i64);
    }

    #[test]
    fn sigma_detector_detects_upper_tail_outlier() {
        // magnitudes = [1, 1, 1, 1, 1, 1, 1, 1, 1, 20]
        // S = 29, SS = 409, N = 10.
        let stats = SigmaStats {
            sum: 29,
            sum_sq: 409,
            n: 10,
        };

        assert!(is_sigma_outlier(20, &stats, 2));
        assert!(!is_sigma_outlier(1, &stats, 2));
    }

    #[test]
    fn sigma_detector_returns_false_for_zero_variance() {
        // magnitudes = [5, 5, 5, 5].
        let stats = SigmaStats {
            sum: 20,
            sum_sq: 100,
            n: 4,
        };

        assert!(!is_sigma_outlier(5, &stats, 2));
    }

    #[test]
    fn sigma_detector_uses_strict_boundary() {
        // N = 2, S = 1, SS = 1:
        // variance_numer = 2×1 - 1² = 1.
        //
        // q = 1:
        // centered = 2×1 - 1 = 1.
        //
        // sigma = 1이면:
        // centered² == sigma² × variance_numer == 1.
        //
        // 조건이 strict `>`이므로 outlier가 아님.
        let stats = SigmaStats {
            sum: 1,
            sum_sq: 1,
            n: 2,
        };

        assert!(!is_sigma_outlier(1, &stats, 1));
    }

    #[test]
    fn sigma_detector_returns_false_for_empty_stats() {
        let stats = SigmaStats {
            sum: 0,
            sum_sq: 0,
            n: 0,
        };

        assert!(!is_sigma_outlier(100, &stats, 2));
    }

    #[test]
    fn shift_i32_returns_input_when_delta_is_zero() {
        assert_eq!(shift_i32(123, 0), 123);
        assert_eq!(shift_i32(-123, 0), -123);
    }

    #[test]
    fn shift_i32_left_shifts_positive_and_negative_values() {
        assert_eq!(shift_i32(3, 2), 12);
        assert_eq!(shift_i32(-3, 2), -12);
    }

    #[test]
    fn shift_i32_saturates_left_shift_overflow() {
        assert_eq!(shift_i32(i32::MAX, 1), i32::MAX);
        assert_eq!(shift_i32(i32::MIN, 1), i32::MIN);

        assert_eq!(shift_i32(1, 31), i32::MAX);
        assert_eq!(shift_i32(-1, 31), i32::MIN);
    }

    #[test]
    fn shift_i32_rounds_right_shift() {
        assert_eq!(shift_i32(7, -1), 4); // 7 / 2 = 3.5 -> 4.
        assert_eq!(shift_i32(-7, -1), -4); // -7 / 2 = -3.5 -> -4.

        assert_eq!(shift_i32(6, -1), 3); // 정확히 나누어지는 경우.
        assert_eq!(shift_i32(-6, -1), -3);

        assert_eq!(shift_i32(5, -1), 3); // 2.5 -> 3.
        assert_eq!(shift_i32(-5, -1), -3); // -2.5 -> -3.
    }

    #[test]
    fn clip_with_residual_preserves_in_range_value() {
        assert_eq!(clip_with_residual(42, -128, 127), (42, 0));
    }

    #[test]
    fn clip_with_residual_captures_positive_overflow() {
        assert_eq!(clip_with_residual(200, -128, 127), (127, 73));
    }

    #[test]
    fn clip_with_residual_captures_negative_overflow() {
        assert_eq!(clip_with_residual(-200, -128, 127), (-128, -72));
    }

    #[test]
    fn clip_with_residual_preserves_original_wide_value() {
        for q in [-200, -128, -1, 0, 1, 127, 200] {
            let (clipped, residual) = clip_with_residual(q, -128, 127);

            assert_eq!(clipped + residual, q);
        }
    }
}
