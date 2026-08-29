use super::{block, config, fold_stripe, stripe, ExsiaError, ExsiaPrecision, ResidualEvent};

fn two_row_k33_blocks() -> Vec<super::BlockResult> {
    vec![
        block(vec![0; 32], 1, 0),
        block(vec![0], 1, 0),
        block(vec![0; 32], 1, 0),
        block(vec![200], 1, 1),
    ]
}

#[test]
fn maps_multi_row_residual_to_local_row_and_k() {
    // Given
    let blocks = two_row_k33_blocks();
    let config = config(ExsiaPrecision::I8, 32);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 2), 33).expect("valid stripe");

    // Then
    assert_eq!(
        result.residual_stripe.events(),
        &[ResidualEvent::new(1, 32, 73)]
    );
}

#[test]
fn maps_second_single_row_stripe_to_manual_qa_coordinates() {
    // Given
    let blocks = [block(vec![0; 32], 1, 0), block(vec![200], 1, 1)];
    let config = config(ExsiaPrecision::I8, 32);

    // When
    let result = fold_stripe(&blocks, &config, stripe(1, 1, 2), 33).expect("valid stripe");
    let event = result.residual_stripe.events()[0];
    let coordinates = (
        result.residual_stripe.stripe_index(),
        result.residual_stripe.row_start(),
        event.local_row(),
        event.global_row(result.residual_stripe.row_start()),
        event.k(),
        event.block_index_in_row(32),
        event.element_index_in_block(32),
    );

    // Then
    assert_eq!(coordinates, (1, 1, 0, 1, 32, 1, 0));
}

#[test]
fn keeps_nonzero_stripe_row_start_out_of_event_coordinate() {
    // Given
    let blocks = two_row_k33_blocks();
    let config = config(ExsiaPrecision::I8, 32);

    // When
    let result =
        fold_stripe(&blocks, &config, stripe(3, 8, 10), 33).expect("valid nonzero-row stripe");
    let event = result.residual_stripe.events()[0];

    // Then
    assert_eq!(event.local_row(), 1);
    assert_eq!(event.global_row(result.residual_stripe.row_start()), 9);
}

#[test]
fn maps_partial_k_block_to_logical_coordinate() {
    // Given
    let blocks = [
        block(vec![0; 32], 1, 0),
        block(vec![0; 32], 1, 0),
        block(vec![200], 1, 1),
    ];
    let config = config(ExsiaPrecision::I8, 32);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 65).expect("valid stripe");

    // Then
    assert_eq!(
        result.residual_stripe.events(),
        &[ResidualEvent::new(0, 64, 73)]
    );
}

#[test]
fn rejects_invalid_partial_block_width() {
    // Given
    let blocks = [
        block(vec![0; 32], 1, 0),
        block(vec![0; 32], 1, 0),
        block(vec![0, 0], 1, 0),
    ];
    let config = config(ExsiaPrecision::I8, 32);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 65);

    // Then
    assert!(matches!(
        result,
        Err(ExsiaError::InvalidStripeBlockWidth {
            stripe_index: 0,
            local_block_index: 2,
            expected: 1,
            actual: 2,
        })
    ));
}

#[test]
fn rejects_too_few_stripe_blocks() {
    // Given
    let blocks = [
        block(vec![0; 32], 1, 0),
        block(vec![0], 1, 0),
        block(vec![0; 32], 1, 0),
    ];
    let config = config(ExsiaPrecision::I8, 32);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 2), 33);

    // Then
    assert!(matches!(
        result,
        Err(ExsiaError::InvalidStripeBlockCount {
            stripe_index: 0,
            expected: 4,
            actual: 3,
        })
    ));
}

#[test]
fn rejects_too_many_stripe_blocks() {
    // Given
    let blocks = [
        block(vec![0; 32], 1, 0),
        block(vec![0], 1, 0),
        block(vec![0; 32], 1, 0),
        block(vec![0], 1, 0),
        block(vec![0; 32], 1, 0),
    ];
    let config = config(ExsiaPrecision::I8, 32);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 2), 33);

    // Then
    assert!(matches!(
        result,
        Err(ExsiaError::InvalidStripeBlockCount {
            stripe_index: 0,
            expected: 4,
            actual: 5,
        })
    ));
}

#[test]
fn rejects_mask_outside_partial_block_width() {
    // Given
    let blocks = [block(vec![0; 32], 1, 0), block(vec![0], 1, 0b10)];
    let config = config(ExsiaPrecision::I8, 32);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 33);

    // Then
    assert!(matches!(
        result,
        Err(ExsiaError::InvalidStripeBlockMask {
            stripe_index: 0,
            local_block_index: 1,
            valid_element_count: 1,
            mask: 0b10,
        })
    ));
}

#[test]
fn accepts_full_width_mask_bit_thirty_one() {
    // Given
    let mut wide = vec![0; 32];
    wide[31] = 200;
    let blocks = [block(wide, 1, 1_u32 << 31)];
    let config = config(ExsiaPrecision::I8, 32);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 1), 32).expect("valid stripe");

    // Then
    assert_eq!(
        result.residual_stripe.events(),
        &[ResidualEvent::new(0, 31, 73)]
    );
}

#[test]
fn preserves_row_major_residual_event_order() {
    // Given
    let blocks = [
        block(vec![200, 0], 1, 0b01),
        block(vec![0, 200], 1, 0b10),
        block(vec![-200, 0], 1, 0b01),
        block(vec![0, -200], 1, 0b10),
    ];
    let config = config(ExsiaPrecision::I8, 2);

    // When
    let result = fold_stripe(&blocks, &config, stripe(0, 0, 2), 4).expect("valid stripe");

    // Then
    assert_eq!(
        result.residual_stripe.events(),
        &[
            ResidualEvent::new(0, 0, 73),
            ResidualEvent::new(0, 3, 73),
            ResidualEvent::new(1, 0, -72),
            ResidualEvent::new(1, 3, -72),
        ]
    );
}
