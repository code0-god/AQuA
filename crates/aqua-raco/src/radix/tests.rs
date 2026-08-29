use super::{
    compose_digits, decompose_residual, radix_contract, RACO_MAX_LANES, RACO_RESIDUAL_MAX,
    RACO_RESIDUAL_MIN,
};
use crate::RacoError;
use aqua_exsia::ExsiaPrecision;

#[test]
fn i4_contract_is_radix16() {
    let contract = radix_contract(ExsiaPrecision::I4);

    assert_eq!(contract.radix(), 16);
    assert_eq!(contract.digit_range(), -8..=7);
    assert_eq!(contract.lane_capacity(), 8);
}

#[test]
fn i8_contract_is_radix256() {
    let contract = radix_contract(ExsiaPrecision::I8);

    assert_eq!(contract.radix(), 256);
    assert_eq!(contract.digit_range(), -128..=127);
    assert_eq!(contract.lane_capacity(), 4);
}

#[test]
fn i16_contract_is_radix65536() {
    let contract = radix_contract(ExsiaPrecision::I16);

    assert_eq!(contract.radix(), 65_536);
    assert_eq!(contract.digit_range(), -32_768..=32_767);
    assert_eq!(contract.lane_capacity(), 2);
}

#[test]
fn decomposes_i8_129_as_minus127_plus_one_radix() {
    let digits = decompose_residual(129, ExsiaPrecision::I8).expect("representable residual");

    assert_eq!(digits.digits(), &[-127, 1, 0, 0]);
    assert_eq!(digits.active_lane_mask(), 0b0011);
    assert_eq!(digits.active_lane_ids().collect::<Vec<_>>(), vec![0, 1]);
}

#[test]
fn decomposes_i8_minus129() {
    let digits = decompose_residual(-129, ExsiaPrecision::I8).expect("representable residual");

    assert_eq!(digits.digits(), &[127, -1, 0, 0]);
}

#[test]
fn decomposes_positive_and_negative_i4_values() {
    let positive = decompose_residual(9, ExsiaPrecision::I4).expect("representable residual");
    let negative = decompose_residual(-9, ExsiaPrecision::I4).expect("representable residual");

    assert_eq!(positive.digits(), &[-7, 1, 0, 0, 0, 0, 0, 0]);
    assert_eq!(negative.digits(), &[7, -1, 0, 0, 0, 0, 0, 0]);
}

#[test]
fn decomposes_i16_values() {
    let digits = decompose_residual(32_769, ExsiaPrecision::I16).expect("representable residual");

    assert_eq!(digits.digits(), &[-32_767, 1]);
}

#[test]
fn round_trips_signed21_edges_and_unit_values() {
    for precision in [ExsiaPrecision::I4, ExsiaPrecision::I8, ExsiaPrecision::I16] {
        for value in [RACO_RESIDUAL_MIN, -1, 0, 1, RACO_RESIDUAL_MAX] {
            let digits = decompose_residual(value, precision).expect("representable residual");
            assert_eq!(compose_digits(&digits, precision), Ok(i64::from(value)));
        }
    }
}

#[test]
fn rejects_values_outside_signed21_range() {
    for value in [RACO_RESIDUAL_MIN - 1, RACO_RESIDUAL_MAX + 1] {
        assert!(matches!(
            decompose_residual(value, ExsiaPrecision::I8),
            Err(RacoError::ResidualOutOfRange {
                value: actual,
                minimum: RACO_RESIDUAL_MIN,
                maximum: RACO_RESIDUAL_MAX,
            }) if actual == value
        ));
    }
}

#[test]
fn active_lane_mask_contains_only_nonzero_digits() {
    let digits = decompose_residual(256, ExsiaPrecision::I4).expect("representable residual");

    assert_eq!(digits.digits(), &[0, 0, 1, 0, 0, 0, 0, 0]);
    assert_eq!(digits.active_lane_mask(), 0b0000_0100);
    assert!(digits.is_lane_active(2));
    assert!(!digits.is_lane_active(1));
    assert!(!digits.is_lane_active(u8::try_from(RACO_MAX_LANES).expect("lane count fits u8")));
}

#[test]
fn composition_preserves_original_lane_positions() {
    let digits = decompose_residual(256, ExsiaPrecision::I4).expect("representable residual");

    assert_eq!(compose_digits(&digits, ExsiaPrecision::I4), Ok(256_i64));
}

#[test]
fn sampled_signed21_values_round_trip_deterministically() {
    const STEP: i64 = 7_919;

    for precision in [ExsiaPrecision::I4, ExsiaPrecision::I8, ExsiaPrecision::I16] {
        let mut value = i64::from(RACO_RESIDUAL_MIN);
        while value <= i64::from(RACO_RESIDUAL_MAX) {
            let residual = i32::try_from(value).expect("signed 21-bit sample");
            let first = decompose_residual(residual, precision).expect("representable residual");
            let second = decompose_residual(residual, precision).expect("representable residual");

            assert_eq!(first, second);
            assert_eq!(compose_digits(&first, precision), Ok(value));
            value += STEP;
        }
    }
}
