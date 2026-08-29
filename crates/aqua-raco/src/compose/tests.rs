use super::compose_correction;
use crate::{
    RacoBlockOutput, RacoBlockWork, RacoCompressedOutput, RacoDigitValues, RacoError,
    RacoStripeWork, RACO_MAX_LANES,
};
use aqua_exsia::ExsiaPrecision;
use aqua_protocol::AQUA_BLOCK_SIZE;

fn single_block(
    precision: ExsiaPrecision,
    lane_ids: &[u8],
    lane_outputs: &[i64],
) -> (RacoStripeWork, RacoCompressedOutput) {
    let mut compact_k = [0_u8; AQUA_BLOCK_SIZE];
    compact_k[0] = 0;
    let mut active_lane_ids = [0_u8; RACO_MAX_LANES];
    active_lane_ids[..lane_ids.len()].copy_from_slice(lane_ids);
    let lane_count = u8::try_from(lane_ids.len()).expect("lane count fits u8");
    (
        RacoStripeWork {
            stripe_index: 0,
            row_start: 0,
            row_count: 1,
            logical_k: 1,
            precision,
            residual_event_count: 1,
            blocks: vec![RacoBlockWork {
                block_index: 0,
                compact_k,
                compact_k_count: 1,
                active_lane_ids,
                active_lane_count: lane_count,
                row_count: 1,
                digits: RacoDigitValues::zeros(precision, lane_ids.len()),
            }],
        },
        RacoCompressedOutput {
            stripe_index: 0,
            row_start: 0,
            row_count: 1,
            logical_j: 1,
            blocks: vec![RacoBlockOutput {
                block_index: 0,
                active_lane_ids,
                active_lane_count: lane_count,
                row_count: 1,
                logical_j: 1,
                values: lane_outputs.to_vec(),
            }],
        },
    )
}

#[test]
fn composes_single_lane() {
    let (work, output) = single_block(ExsiaPrecision::I8, &[0], &[5]);

    let correction = compose_correction(&work, &output).expect("valid composition");

    assert_eq!(correction.values(), &[5]);
}

#[test]
fn composes_i8_minus127_plus_one_radix() {
    let (work, output) = single_block(ExsiaPrecision::I8, &[0, 1], &[-4_064, 32]);

    let correction = compose_correction(&work, &output).expect("valid composition");

    assert_eq!(correction.values(), &[4_128]);
}

#[test]
fn preserves_sparse_original_lane_ids() {
    let (work, output) = single_block(ExsiaPrecision::I4, &[0, 2], &[1, 1]);

    let correction = compose_correction(&work, &output).expect("valid composition");

    assert_eq!(correction.values(), &[257]);
}

#[test]
fn sums_multiple_blocks() {
    let (mut work, mut output) = single_block(ExsiaPrecision::I8, &[0], &[3]);
    let mut second_work = work.blocks[0].clone();
    second_work.block_index = 1;
    work.blocks.push(second_work);
    let mut second_output = output.blocks[0].clone();
    second_output.block_index = 1;
    second_output.values[0] = 4;
    output.blocks.push(second_output);

    let correction = compose_correction(&work, &output).expect("valid composition");

    assert_eq!(correction.values(), &[7]);
}

#[test]
fn composes_multiple_rows_and_j() {
    let (mut work, mut output) = single_block(ExsiaPrecision::I8, &[0], &[1]);
    work.row_count = 2;
    work.blocks[0].row_count = 2;
    work.blocks[0].digits =
        RacoDigitValues::from_i32(ExsiaPrecision::I8, &[0, 0]).expect("valid digits");
    output.row_count = 2;
    output.logical_j = 2;
    output.blocks[0].row_count = 2;
    output.blocks[0].logical_j = 2;
    output.blocks[0].values = vec![1, 2, 3, 4];

    let correction = compose_correction(&work, &output).expect("valid composition");

    assert_eq!(correction.values(), &[1, 2, 3, 4]);
}

#[test]
fn rejects_work_output_block_mismatch() {
    let (work, mut output) = single_block(ExsiaPrecision::I8, &[0], &[1]);
    output.blocks[0].block_index = 1;

    assert!(matches!(
        compose_correction(&work, &output),
        Err(RacoError::WorkOutputMismatch { .. })
    ));
}

#[test]
fn rejects_lane_id_mismatch() {
    let (work, mut output) = single_block(ExsiaPrecision::I8, &[0], &[1]);
    output.blocks[0].active_lane_ids[0] = 1;

    assert!(matches!(
        compose_correction(&work, &output),
        Err(RacoError::WorkOutputMismatch { .. })
    ));
}

#[test]
fn rejects_composition_overflow() {
    let (work, output) = single_block(ExsiaPrecision::I8, &[0, 1], &[0, i64::MAX]);

    assert_eq!(
        compose_correction(&work, &output),
        Err(RacoError::CompositionOverflow {
            block_index: 0,
            local_row: 0,
            j: 0,
        })
    );
}

#[test]
fn rejects_final_correction_overflow() {
    let (mut work, mut output) = single_block(ExsiaPrecision::I8, &[0], &[i64::MAX]);
    let mut second_work = work.blocks[0].clone();
    second_work.block_index = 1;
    work.blocks.push(second_work);
    let mut second_output = output.blocks[0].clone();
    second_output.block_index = 1;
    output.blocks.push(second_output);

    assert_eq!(
        compose_correction(&work, &output),
        Err(RacoError::CorrectionOverflow { local_row: 0, j: 0 })
    );
}
