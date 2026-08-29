use super::{checked_dot_output, execute_integer_reference, DenseWeightCodes, DotCoordinate};
use crate::{RacoBlockWork, RacoDigitValues, RacoError, RacoStripeWork, RACO_MAX_LANES};
use aqua_exsia::ExsiaPrecision;
use aqua_protocol::AQUA_BLOCK_SIZE;

fn contract_arrays(
    compact: &[u8],
    lanes: &[u8],
) -> ([u8; AQUA_BLOCK_SIZE], u8, [u8; RACO_MAX_LANES], u8) {
    let mut compact_k = [0_u8; AQUA_BLOCK_SIZE];
    compact_k[..compact.len()].copy_from_slice(compact);
    let mut active_lane_ids = [0_u8; RACO_MAX_LANES];
    active_lane_ids[..lanes.len()].copy_from_slice(lanes);
    (
        compact_k,
        u8::try_from(compact.len()).expect("compact count fits u8"),
        active_lane_ids,
        u8::try_from(lanes.len()).expect("lane count fits u8"),
    )
}

#[test]
fn executes_single_block_single_lane() {
    let (compact_k, compact_k_count, active_lane_ids, active_lane_count) =
        contract_arrays(&[0, 2], &[0]);
    let work = RacoStripeWork {
        stripe_index: 0,
        row_start: 0,
        row_count: 1,
        logical_k: 3,
        precision: ExsiaPrecision::I8,
        residual_event_count: 2,
        blocks: vec![RacoBlockWork {
            block_index: 0,
            compact_k,
            compact_k_count,
            active_lane_ids,
            active_lane_count,
            row_count: 1,
            digits: RacoDigitValues::from_i32(ExsiaPrecision::I8, &[2, -1]).expect("valid digits"),
        }],
    };
    let weights = DenseWeightCodes::new(&[3, 4, 0, 0, 5, 6], 3, 2).expect("valid weights");

    let output = execute_integer_reference(&work, &weights).expect("valid execution");

    assert_eq!(output.blocks()[0].values(), &[1, 2]);
}

#[test]
fn executes_multiple_active_lanes_and_rows() {
    let (compact_k, compact_k_count, active_lane_ids, active_lane_count) =
        contract_arrays(&[0], &[0, 2]);
    let work = RacoStripeWork {
        stripe_index: 0,
        row_start: 0,
        row_count: 2,
        logical_k: 1,
        precision: ExsiaPrecision::I4,
        residual_event_count: 4,
        blocks: vec![RacoBlockWork {
            block_index: 0,
            compact_k,
            compact_k_count,
            active_lane_ids,
            active_lane_count,
            row_count: 2,
            digits: RacoDigitValues::from_i32(ExsiaPrecision::I4, &[1, 2, -3, 4])
                .expect("valid digits"),
        }],
    };
    let weights = DenseWeightCodes::new(&[5], 1, 1).expect("valid weights");

    let output = execute_integer_reference(&work, &weights).expect("valid execution");

    assert_eq!(output.blocks()[0].values(), &[5, 10, -15, 20]);
}

#[test]
fn executes_multiple_blocks_using_original_global_k() {
    let (first_k, first_count, first_lanes, first_lane_count) = contract_arrays(&[1], &[0]);
    let (second_k, second_count, second_lanes, second_lane_count) = contract_arrays(&[0], &[0]);
    let work = RacoStripeWork {
        stripe_index: 0,
        row_start: 0,
        row_count: 1,
        logical_k: 33,
        precision: ExsiaPrecision::I8,
        residual_event_count: 2,
        blocks: vec![
            RacoBlockWork {
                block_index: 0,
                compact_k: first_k,
                compact_k_count: first_count,
                active_lane_ids: first_lanes,
                active_lane_count: first_lane_count,
                row_count: 1,
                digits: RacoDigitValues::from_i32(ExsiaPrecision::I8, &[2]).expect("valid digits"),
            },
            RacoBlockWork {
                block_index: 1,
                compact_k: second_k,
                compact_k_count: second_count,
                active_lane_ids: second_lanes,
                active_lane_count: second_lane_count,
                row_count: 1,
                digits: RacoDigitValues::from_i32(ExsiaPrecision::I8, &[3]).expect("valid digits"),
            },
        ],
    };
    let mut codes = vec![0; 33];
    codes[1] = -5;
    codes[32] = 7;
    let weights = DenseWeightCodes::new(&codes, 33, 1).expect("valid weights");

    let output = execute_integer_reference(&work, &weights).expect("valid execution");

    assert_eq!(output.blocks()[0].values(), &[-10]);
    assert_eq!(output.blocks()[1].values(), &[21]);
}

#[test]
fn rejects_weight_element_count_mismatch() {
    assert_eq!(
        DenseWeightCodes::new(&[1, 2, 3], 2, 2),
        Err(RacoError::WeightElementCountMismatch {
            expected: 4,
            actual: 3,
        })
    );
}

#[test]
fn rejects_logical_k_mismatch() {
    let work = RacoStripeWork {
        stripe_index: 0,
        row_start: 0,
        row_count: 1,
        logical_k: 2,
        precision: ExsiaPrecision::I8,
        residual_event_count: 0,
        blocks: Vec::new(),
    };
    let weights = DenseWeightCodes::new(&[1], 1, 1).expect("valid weights");

    assert_eq!(
        execute_integer_reference(&work, &weights),
        Err(RacoError::WeightKDoesNotMatch {
            residual_k: 2,
            weight_k: 1,
        })
    );
}

#[test]
fn rejects_dot_overflow_at_checked_output_boundary() {
    assert_eq!(
        checked_dot_output(
            i128::from(i64::MAX) + 1,
            DotCoordinate {
                block_index: 2,
                lane_id: 1,
                local_row: 3,
                j: 4,
            },
        ),
        Err(RacoError::DotProductOverflow {
            block_index: 2,
            lane_id: 1,
            local_row: 3,
            j: 4,
        })
    );
}
