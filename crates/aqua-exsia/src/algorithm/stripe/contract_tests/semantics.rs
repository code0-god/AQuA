use super::{
    block, config, fold_stripe, math, stripe, ExsiaPrecision, QuantizedValues, ResidualEvent,
};

#[test]
fn folds_single_exponent_without_promotion() {
    // Given
    let blocks = [block(vec![20; 32], 1, 0), block(vec![30], 1, 0)];
    let config = config(ExsiaPrecision::I8);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 33).expect("valid stripe");

    // Then
    let mut expected = vec![20; 32];
    expected.push(30);
    assert_eq!(result.quantized, QuantizedValues::I8(expected));
    assert_eq!(result.exponent, 1);
    assert_eq!(result.theta, 1 - config.rho());
    assert!(result.residual_stripe.is_empty());
}

#[test]
fn uses_second_distinct_exponent_for_stripe_scale() {
    // Given
    let blocks = [block(vec![10; 32], 3, 0), block(vec![10], 1, 0)];
    let config = config(ExsiaPrecision::I8);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 33).expect("valid stripe");

    // Then
    let mut expected = vec![40; 32];
    expected.push(10);
    assert_eq!(result.quantized, QuantizedValues::I8(expected));
    assert_eq!(result.exponent, 1);
    assert_eq!(result.theta, -5);
    assert!(result.residual_stripe.is_empty());
}

#[test]
fn promotes_top_exponent_block_for_residual_capture() {
    // Given
    let mut promoted = vec![0; 32];
    promoted[0] = 100;
    let blocks = [block(promoted, 3, 0), block(vec![10], 1, 0)];
    let config = config(ExsiaPrecision::I8);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 33).expect("valid stripe");

    // Then
    let mut expected = vec![0; 33];
    expected[0] = 127;
    expected[32] = 10;
    assert_eq!(result.quantized, QuantizedValues::I8(expected));
    assert_eq!(result.exponent, 1);
    assert_eq!(
        result.residual_stripe.events(),
        &[ResidualEvent::new(0, 0, 273)]
    );
}

#[test]
fn captures_existing_block_outlier_residual() {
    // Given
    let blocks = [block(vec![200], 1, 1_u32)];
    let config = config(ExsiaPrecision::I8);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 1).expect("valid stripe");

    // Then
    assert_eq!(result.quantized, QuantizedValues::I8(vec![127]));
    assert_eq!(
        result.residual_stripe.events(),
        &[ResidualEvent::new(0, 0, 73)]
    );
}

#[test]
fn omits_selected_outlier_without_clipping_residual() {
    // Given
    let blocks = [block(vec![10], 1, 1_u32)];
    let config = config(ExsiaPrecision::I8);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 1).expect("valid stripe");

    // Then
    assert_eq!(result.quantized, QuantizedValues::I8(vec![10]));
    assert!(result.residual_stripe.is_empty());
}

#[test]
fn folds_all_invalid_zero_blocks_at_zero_exponent() {
    // Given
    let blocks = [
        block(vec![0; 32], math::NEG_INF_EXP, 0),
        block(vec![0], math::NEG_INF_EXP, 0),
    ];
    let config = config(ExsiaPrecision::I8);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 33).expect("valid stripe");

    // Then
    assert_eq!(result.quantized, QuantizedValues::I8(vec![0; 33]));
    assert_eq!(result.exponent, 0);
    assert_eq!(result.theta, -config.rho());
    assert!(result.residual_stripe.is_empty());
}

#[test]
fn clips_i4_after_scale_alignment() {
    // Given
    let mut promoted = vec![0; 32];
    promoted[0] = 6;
    let blocks = [block(promoted, 1, 0), block(vec![2], 0, 0)];
    let config = config(ExsiaPrecision::I4);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 33).expect("valid stripe");

    // Then
    let mut expected = vec![0; 33];
    expected[0] = 7;
    expected[32] = 2;
    assert_eq!(result.quantized, QuantizedValues::I4(expected));
    assert_eq!(result.exponent, 0);
    assert_eq!(
        result.residual_stripe.events(),
        &[ResidualEvent::new(0, 0, 5)]
    );
}

#[test]
fn produces_i8_quantized_values() {
    // Given
    let blocks = [block(vec![-128, 0, 127], 0, 0)];
    let config = config(ExsiaPrecision::I8);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 3).expect("valid stripe");

    // Then
    assert_eq!(result.quantized, QuantizedValues::I8(vec![-128, 0, 127]));
}

#[test]
fn produces_i16_quantized_values_without_clipping() {
    // Given
    let blocks = [block(vec![-32_000, 0, 30_000], 0, 0)];
    let config = config(ExsiaPrecision::I16);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 3).expect("valid stripe");

    // Then
    assert_eq!(
        result.quantized,
        QuantizedValues::I16(vec![-32_000, 0, 30_000])
    );
    assert!(result.residual_stripe.is_empty());
}

#[test]
fn preserves_logical_element_order() {
    // Given
    let blocks = [
        block(vec![1; 32], 0, 0),
        block(vec![2; 32], 0, 0),
        block(vec![3], 0, 0),
    ];
    let config = config(ExsiaPrecision::I8);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 65).expect("valid stripe");

    // Then
    let mut expected = vec![1; 32];
    expected.extend(vec![2; 32]);
    expected.push(3);
    assert_eq!(result.quantized, QuantizedValues::I8(expected));
}
