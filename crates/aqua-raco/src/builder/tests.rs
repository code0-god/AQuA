use super::{build_from_events, StripeMetadata};
use crate::{RacoDigitValues, RacoError};
use aqua_exsia::ExsiaPrecision;

fn build(
    metadata: StripeMetadata,
    precision: ExsiaPrecision,
    events: &[(usize, usize, i32)],
) -> Result<Option<crate::RacoStripeWork>, RacoError> {
    build_from_events(metadata, precision, events.iter().copied())
}

const fn metadata(row_count: usize, logical_k: usize) -> StripeMetadata {
    StripeMetadata {
        stripe_index: 3,
        row_start: 8,
        row_count,
        logical_k,
    }
}

#[test]
fn returns_none_for_empty_residual_stripe() {
    assert_eq!(build(metadata(1, 32), ExsiaPrecision::I8, &[]), Ok(None));
}

#[test]
fn compacts_k_rows_and_active_lanes_canonically() {
    let work = build(
        metadata(2, 32),
        ExsiaPrecision::I8,
        &[(1, 7, 129), (0, 3, -129), (0, 7, 1)],
    )
    .expect("valid residuals")
    .expect("nonempty work");
    let block = &work.blocks()[0];

    assert_eq!(block.compact_k(), &[3, 7]);
    assert_eq!(block.active_lane_ids(), &[0, 1]);
    assert_eq!(
        block.digits(),
        &RacoDigitValues::from_i32(ExsiaPrecision::I8, &[127, 1, 0, -127, -1, 0, 0, 1])
            .expect("valid digits")
    );
    assert_eq!(block.digit(0, 0, 0), Ok(127));
    assert_eq!(block.digit(1, 1, 1), Ok(1));
}

#[test]
fn groups_and_orders_shared_32_element_blocks() {
    let work = build(
        metadata(1, 65),
        ExsiaPrecision::I8,
        &[(0, 64, 1), (0, 33, 1), (0, 1, 1)],
    )
    .expect("valid residuals")
    .expect("nonempty work");

    assert_eq!(
        work.blocks()
            .iter()
            .map(crate::RacoBlockWork::block_index)
            .collect::<Vec<_>>(),
        vec![0, 1, 2]
    );
    assert_eq!(work.blocks()[0].compact_k(), &[1]);
    assert_eq!(work.blocks()[1].compact_k(), &[1]);
    assert_eq!(work.blocks()[2].compact_k(), &[0]);
}

#[test]
fn compacts_only_nonzero_original_lane_ids() {
    let work = build(metadata(1, 32), ExsiaPrecision::I4, &[(0, 5, 256)])
        .expect("valid residual")
        .expect("nonempty work");
    let block = &work.blocks()[0];

    assert_eq!(block.active_lane_ids(), &[2]);
    assert_eq!(block.digit(0, 0, 0), Ok(1));
}

#[test]
fn builds_i4_i8_and_i16_digit_payloads() {
    for (precision, residual, expected) in [
        (ExsiaPrecision::I4, 9, vec![-7, 1]),
        (ExsiaPrecision::I8, 129, vec![-127, 1]),
        (ExsiaPrecision::I16, 32_769, vec![-32_767, 1]),
    ] {
        let work = build(metadata(1, 1), precision, &[(0, 0, residual)])
            .expect("valid residual")
            .expect("nonempty work");
        let block = &work.blocks()[0];

        assert_eq!(block.precision(), precision);
        assert_eq!(
            (0..block.active_lane_ids().len())
                .map(|lane| block.digit(lane, 0, 0).expect("valid digit"))
                .collect::<Vec<_>>(),
            expected
        );
    }
}

#[test]
fn rejects_duplicate_local_row_k() {
    assert_eq!(
        build(metadata(1, 32), ExsiaPrecision::I8, &[(0, 7, 1), (0, 7, 2)]),
        Err(RacoError::DuplicateResidualCoordinate { local_row: 0, k: 7 })
    );
}

#[test]
fn rejects_invalid_residual_events() {
    assert!(matches!(
        build(metadata(1, 32), ExsiaPrecision::I8, &[(1, 0, 1)]),
        Err(RacoError::ResidualRowOutOfBounds {
            local_row: 1,
            row_count: 1,
        })
    ));
    assert!(matches!(
        build(metadata(1, 32), ExsiaPrecision::I8, &[(0, 32, 1)]),
        Err(RacoError::ResidualKOutOfBounds {
            k: 32,
            logical_k: 32,
        })
    ));
    assert_eq!(
        build(metadata(1, 32), ExsiaPrecision::I8, &[(0, 0, 0)]),
        Err(RacoError::ZeroResidual { local_row: 0, k: 0 })
    );
    assert!(matches!(
        build(metadata(1, 32), ExsiaPrecision::I8, &[(0, 0, 1_048_576)]),
        Err(RacoError::ResidualOutOfRange { .. })
    ));
}

#[test]
fn preserves_stripe_metadata_and_event_count() {
    let work = build(
        metadata(2, 33),
        ExsiaPrecision::I8,
        &[(0, 0, 1), (1, 32, 2)],
    )
    .expect("valid residuals")
    .expect("nonempty work");

    assert_eq!(work.stripe_index(), 3);
    assert_eq!(work.row_start(), 8);
    assert_eq!(work.row_count(), 2);
    assert_eq!(work.logical_k(), 33);
    assert_eq!(work.precision(), ExsiaPrecision::I8);
    assert_eq!(work.residual_event_count(), 2);
}

#[test]
fn same_coordinate_set_ignores_input_event_order() {
    let forward = [(0, 1, 129), (1, 7, -129), (0, 33, 256)];
    let reverse = [(0, 33, 256), (1, 7, -129), (0, 1, 129)];

    assert_eq!(
        build(metadata(2, 65), ExsiaPrecision::I8, &forward),
        build(metadata(2, 65), ExsiaPrecision::I8, &reverse)
    );
}
