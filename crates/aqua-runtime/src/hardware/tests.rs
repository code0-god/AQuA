use super::*;
use aqua_protocol::AQUA_BLOCK_SIZE;

fn complete_builder(array_dim: usize) -> AquaHardwareGeometryBuilder {
    AquaHardwareGeometry::builder(array_dim)
        .activation_spad(4, 1024)
        .weight_spad(4, 1024)
        .accumulator(2, 512)
        .exsia_slots(2, 1 << 20)
        .element_bits(8, 8, 32)
        .hp1_metadata(1 << 20, 16, 16)
        .exsia_layout(32, 16, 32)
}

#[test]
fn rejects_zero_geometry() {
    // Given
    let builder = complete_builder(0);

    // When
    let error = builder.build().expect_err("zero DIM must fail");

    // Then
    assert!(matches!(
        error,
        HardwareGeometryError::ZeroField { field: "array_dim" }
    ));
}

#[test]
fn rejects_incompatible_dim_and_block_size() {
    // Given
    let builder = complete_builder(24);

    // When
    let error = builder.build().expect_err("DIM24 is incompatible");

    // Then
    assert!(matches!(
        error,
        HardwareGeometryError::IncompatibleArrayDim {
            array_dim: 24,
            block_size: AQUA_BLOCK_SIZE,
        }
    ));
}

#[test]
fn rejects_unimplemented_compatible_dim() {
    // Given
    let builder = complete_builder(8);

    // When
    let error = builder.build().expect_err("DIM8 is not supported");

    // Then
    assert!(matches!(
        error,
        HardwareGeometryError::UnsupportedArrayDim { array_dim: 8 }
    ));
}

#[test]
fn rejects_zero_memory_geometry() {
    // Given
    let builder = AquaHardwareGeometry::builder(16)
        .activation_spad(0, 1024)
        .weight_spad(4, 1024)
        .accumulator(2, 512)
        .exsia_slots(2, 1 << 20)
        .element_bits(8, 8, 32)
        .hp1_metadata(1 << 20, 16, 16)
        .exsia_layout(32, 16, 32);

    // When
    let error = builder.build().expect_err("zero bank count must fail");

    // Then
    assert!(matches!(
        error,
        HardwareGeometryError::ZeroField {
            field: "activation_spad_banks"
        }
    ));
}

#[test]
fn rejects_incompatible_accumulator_banks() {
    // Given
    let builder = AquaHardwareGeometry::builder(16)
        .activation_spad(4, 1024)
        .weight_spad(4, 1024)
        .accumulator(3, 512)
        .exsia_slots(2, 1 << 20)
        .element_bits(8, 8, 32)
        .hp1_metadata(1 << 20, 16, 16)
        .exsia_layout(32, 16, 32);

    // When
    let error = builder.build().expect_err("bank mapping must fail");

    // Then
    assert!(matches!(
        error,
        HardwareGeometryError::IncompatibleAccumulatorBanks {
            array_dim: 16,
            banks: 3,
        }
    ));
}

#[test]
fn rejects_geometry_capacity_overflow() {
    // Given
    let builder = AquaHardwareGeometry::builder(32)
        .activation_spad(usize::MAX, 2)
        .weight_spad(1, 1)
        .accumulator(1, 1)
        .exsia_slots(1, 1)
        .element_bits(8, 8, 32)
        .hp1_metadata(1, 16, 16)
        .exsia_layout(32, 16, 32);

    // When
    let error = builder.build().expect_err("capacity overflow must fail");

    // Then
    assert!(matches!(
        error,
        HardwareGeometryError::CapacityOverflow {
            resource: "activation_spad"
        }
    ));
}

#[test]
fn double_buffering_reduces_usable_capacity() {
    // Given
    let single = complete_builder(32)
        .build()
        .expect("single-buffer geometry");
    let double = complete_builder(32)
        .double_buffering(true, true, true)
        .build()
        .expect("double-buffer geometry");

    // When
    let single_rows = (
        single.usable_activation_spad_rows(),
        single.usable_weight_spad_rows(),
        single.usable_accumulator_rows(),
    );
    let double_rows = (
        double.usable_activation_spad_rows(),
        double.usable_weight_spad_rows(),
        double.usable_accumulator_rows(),
    );

    // Then
    assert_eq!(double_rows.0, single_rows.0 / 2);
    assert_eq!(double_rows.1, single_rows.1 / 2);
    assert_eq!(double_rows.2, single_rows.2 / 2);
}

#[test]
fn supports_dim16() {
    // Given
    let builder = complete_builder(16);

    // When
    let geometry = builder.build().expect("DIM16");

    // Then
    assert_eq!(geometry.array_dim(), 16);
}

#[test]
fn supports_dim32() {
    // Given
    let builder = complete_builder(32);

    // When
    let geometry = builder.build().expect("DIM32");

    // Then
    assert_eq!(geometry.array_dim(), 32);
}

#[test]
fn supports_dim64() {
    // Given
    let builder = complete_builder(64);

    // When
    let geometry = builder.build().expect("DIM64");

    // Then
    assert_eq!(geometry.array_dim(), 64);
}
