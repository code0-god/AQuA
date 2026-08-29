use super::{
    RacoBlockOutput, RacoBlockWork, RacoCompressedOutput, RacoDigitValues, RacoStripeWork,
};
use crate::{RacoError, RACO_MAX_LANES};
use aqua_exsia::ExsiaPrecision;
use aqua_protocol::AQUA_BLOCK_SIZE;

#[test]
fn digit_values_enforce_precision_range() {
    let mut values = RacoDigitValues::zeros(ExsiaPrecision::I4, 2);

    assert_eq!(values.set_i32(0, -8), Ok(()));
    assert_eq!(values.set_i32(1, 7), Ok(()));
    assert_eq!(values.get_i32(0), Ok(-8));
    assert_eq!(values.get_i32(1), Ok(7));
    assert_eq!(
        values.set_i32(1, 8),
        Err(RacoError::InvalidDigit {
            precision: ExsiaPrecision::I4,
            value: 8,
        })
    );
}

#[test]
fn block_work_uses_lane_row_compact_k_payload_order() {
    let mut compact_k = [0_u8; AQUA_BLOCK_SIZE];
    compact_k[..2].copy_from_slice(&[3, 7]);
    let mut active_lane_ids = [0_u8; RACO_MAX_LANES];
    active_lane_ids[..2].copy_from_slice(&[0, 2]);
    let digits = RacoDigitValues::from_i32(ExsiaPrecision::I8, &[1, 2, 3, 4, 5, 6, 7, 8])
        .expect("valid digits");
    let work = RacoBlockWork {
        block_index: 4,
        compact_k,
        compact_k_count: 2,
        active_lane_ids,
        active_lane_count: 2,
        row_count: 2,
        digits,
    };

    assert_eq!(work.compact_k(), &[3, 7]);
    assert_eq!(work.active_lane_ids(), &[0, 2]);
    assert_eq!(work.digit(0, 0, 0), Ok(1));
    assert_eq!(work.digit(0, 1, 1), Ok(4));
    assert_eq!(work.digit(1, 0, 0), Ok(5));
    assert_eq!(work.digit(1, 1, 1), Ok(8));
}

#[test]
fn block_output_uses_lane_row_j_payload_order() {
    let mut active_lane_ids = [0_u8; RACO_MAX_LANES];
    active_lane_ids[..2].copy_from_slice(&[0, 2]);
    let output = RacoBlockOutput {
        block_index: 4,
        active_lane_ids,
        active_lane_count: 2,
        row_count: 2,
        logical_j: 2,
        values: vec![1, 2, 3, 4, 5, 6, 7, 8],
    };

    assert_eq!(output.value(0, 0, 0), Ok(1));
    assert_eq!(output.value(0, 1, 1), Ok(4));
    assert_eq!(output.value(1, 0, 0), Ok(5));
    assert_eq!(output.value(1, 1, 1), Ok(8));
}

#[test]
fn stripe_contracts_expose_read_only_stage_metadata() {
    let work = RacoStripeWork {
        stripe_index: 3,
        row_start: 8,
        row_count: 2,
        logical_k: 65,
        precision: ExsiaPrecision::I8,
        residual_event_count: 0,
        blocks: Vec::new(),
    };
    let output = RacoCompressedOutput {
        stripe_index: 3,
        row_start: 8,
        row_count: 2,
        logical_j: 4,
        blocks: Vec::new(),
    };

    assert_eq!(work.stripe_index(), 3);
    assert_eq!(work.row_start(), 8);
    assert_eq!(work.row_count(), 2);
    assert_eq!(work.logical_k(), 65);
    assert_eq!(work.precision(), ExsiaPrecision::I8);
    assert_eq!(work.residual_event_count(), 0);
    assert!(work.blocks().is_empty());
    assert_eq!(output.stripe_index(), 3);
    assert_eq!(output.logical_j(), 4);
    assert!(output.blocks().is_empty());
}
