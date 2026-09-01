use super::*;
use crate::hardware::{AquaHardwareGeometry, AquaHardwareGeometryBuilder, Hp1MetaGeometry};

#[derive(Clone, Copy)]
struct GeometryFixture {
    dim: usize,
    activation_rows: usize,
    weight_rows: usize,
    accumulator_rows: usize,
    exsia_slot_bytes: usize,
    hp1_block_entries: usize,
    hp1_row_entries: usize,
    double_buffered: bool,
}

impl GeometryFixture {
    const fn generous(dim: usize) -> Self {
        Self {
            dim,
            activation_rows: 16_384,
            weight_rows: 16_384,
            accumulator_rows: 4096,
            exsia_slot_bytes: 1 << 30,
            hp1_block_entries: 4096,
            hp1_row_entries: 4096,
            double_buffered: false,
        }
    }

    fn builder(self) -> AquaHardwareGeometryBuilder {
        AquaHardwareGeometry::builder(self.dim)
            .activation_spad(1, self.activation_rows)
            .weight_spad(1, self.weight_rows)
            .accumulator(self.dim, self.accumulator_rows)
            .exsia_slots(2, self.exsia_slot_bytes)
            .element_bits(8, 8, 32)
            .hp1_metadata(Hp1MetaGeometry {
                block_entries: self.hp1_block_entries,
                row_entries: self.hp1_row_entries,
                left_shift_bits: 16,
                row_right_shift_bits: 16,
            })
            .exsia_layout(32, 16, 32)
            .double_buffering(
                self.double_buffered,
                self.double_buffered,
                self.double_buffered,
            )
    }

    fn build(self) -> AquaHardwareGeometry {
        self.builder().build().expect("valid fixture geometry")
    }
}

fn select(fixture: GeometryFixture, shape: MatmulShape) -> Result<AquaTilePlan, TilingError> {
    AquaTileSelector::new(fixture.build()).select(shape)
}

#[test]
fn rejects_zero_matmul_dimension() {
    // When
    let error = MatmulShape::new(0, 16, 16).expect_err("zero M must fail");

    // Then
    assert!(matches!(
        error,
        TilingError::ZeroMatmulDimension { dimension: "m" }
    ));
}

#[test]
fn rejects_matmul_element_count_overflow() {
    // Given
    let m = usize::MAX;

    // When
    let error = MatmulShape::new(m, 2, 1).expect_err("activation size overflow");

    // Then
    assert!(matches!(
        error,
        TilingError::ArithmeticOverflow {
            calculation: "output element count"
        }
    ));
}

#[test]
fn pads_dimensions_to_array_dim() {
    // Given
    let shape = MatmulShape::new(17, 18, 33).expect("shape");

    // When
    let plan = select(GeometryFixture::generous(16), shape).expect("plan");

    // Then
    assert_eq!(plan.padded_m(), 32);
    assert_eq!(plan.padded_n(), 32);
    assert_eq!(plan.padded_k(), 48);
}

#[test]
fn selects_deterministically() {
    // Given
    let geometry = GeometryFixture::generous(32).build();
    let selector = AquaTileSelector::new(geometry);
    let shape = MatmulShape::new(191, 768, 768).expect("shape");

    // When
    let first = selector.select(shape).expect("first");
    let second = selector.select(shape).expect("second");

    // Then
    assert_eq!(first, second);
}

#[test]
fn preserves_j_i_k_growth_order() {
    // Given
    let fixture = GeometryFixture {
        dim: 16,
        activation_rows: 8192,
        weight_rows: 8192,
        accumulator_rows: 1024,
        exsia_slot_bytes: 1 << 30,
        hp1_block_entries: 4096,
        hp1_row_entries: 4096,
        double_buffered: true,
    };
    let shape = MatmulShape::new(128, 128, 128).expect("shape");

    // When
    let plan = select(fixture, shape).expect("plan");

    // Then
    assert_eq!(plan.factors(), TileFactors::new(5, 6, 8));
}

#[test]
fn respects_activation_capacity() {
    // Given
    let mut fixture = GeometryFixture::generous(16);
    fixture.activation_rows = 128;
    let geometry = fixture.build();
    let selector = AquaTileSelector::new(geometry);

    // When
    let plan = selector
        .select(MatmulShape::new(128, 128, 128).expect("shape"))
        .expect("plan");

    // Then
    assert!(plan.activation_spad_rows() <= geometry.usable_activation_spad_rows());
}

#[test]
fn respects_weight_capacity() {
    // Given
    let mut fixture = GeometryFixture::generous(16);
    fixture.weight_rows = 128;
    let geometry = fixture.build();

    // When
    let plan = AquaTileSelector::new(geometry)
        .select(MatmulShape::new(128, 128, 128).expect("shape"))
        .expect("plan");

    // Then
    assert!(plan.weight_spad_rows() <= geometry.usable_weight_spad_rows());
}

#[test]
fn selector_never_returns_plan_exceeding_accumulator_rows_per_bank() {
    // Given
    let mut fixture = GeometryFixture::generous(16);
    fixture.accumulator_rows = 128;
    fixture.double_buffered = true;
    let geometry = fixture.build();

    // When
    let plan = AquaTileSelector::new(geometry)
        .select(MatmulShape::new(128, 128, 128).expect("shape"))
        .expect("plan");

    // Then
    assert!(plan.accumulator_rows_per_bank() <= geometry.accumulator_rows_per_bank() / 2);
}

#[test]
fn accumulator_capacity_is_checked_per_bank() {
    // Given
    let fixture = GeometryFixture::generous(16);
    let geometry = fixture.build();
    let shape = MatmulShape::new(32, 48, 16).expect("shape");
    let factors = TileFactors::new(2, 3, 1);

    // When
    let usage = capacity::resource_usage(geometry, shape, factors).expect("usage");

    // Then
    assert_eq!(usage.accumulator_rows_per_bank, 2 * 3 * 16);
}

#[test]
fn block_scale_storage_includes_zero_block_flag() {
    // Given
    let geometry = GeometryFixture::generous(16)
        .builder()
        .hp1_metadata(Hp1MetaGeometry {
            block_entries: 8,
            row_entries: 4,
            left_shift_bits: 5,
            row_right_shift_bits: 4,
        })
        .build()
        .expect("asymmetric HP1 metadata geometry");
    let shape = MatmulShape::new(16, 16, 32).expect("shape");
    let factors = TileFactors::new(1, 1, 2);

    // When
    let usage = capacity::resource_usage(geometry, shape, factors).expect("usage");

    // Then
    assert_eq!(usage.hp1_metadata_bytes, 20);
}

#[test]
fn selector_respects_block_metadata_depth() {
    // Given
    let mut fixture = GeometryFixture::generous(16);
    fixture.hp1_block_entries = 1;
    let geometry = fixture.build();

    // When
    let plan = AquaTileSelector::new(geometry)
        .select(MatmulShape::new(16, 64, 128).expect("shape"))
        .expect("plan");

    // Then
    assert!(plan.hp1_block_metadata_entries() <= geometry.hp1_block_metadata_entries());
}

#[test]
fn selector_respects_row_metadata_depth() {
    // Given
    let mut fixture = GeometryFixture::generous(16);
    fixture.hp1_row_entries = 1;
    let geometry = fixture.build();

    // When
    let plan = AquaTileSelector::new(geometry)
        .select(MatmulShape::new(16, 64, 32).expect("shape"))
        .expect("plan");

    // Then
    assert!(plan.hp1_row_metadata_entries() <= geometry.hp1_row_metadata_entries());
}

#[test]
fn respects_exsia_slot_capacity() {
    // Given
    let mut fixture = GeometryFixture::generous(16);
    fixture.exsia_slot_bytes = 2144;
    let geometry = fixture.build();

    // When
    let plan = AquaTileSelector::new(geometry)
        .select(MatmulShape::new(16, 32, 32).expect("shape"))
        .expect("plan");

    // Then
    assert!(plan.exsia_slot_bytes() <= geometry.exsia_slot_bytes());
}

#[test]
fn exsia_slot_accounts_full_logical_k() {
    // Given
    let mut fixture = GeometryFixture::generous(16);
    fixture.activation_rows = 16;
    let shape = MatmulShape::new(16, 16, 128).expect("shape");

    // When
    let plan = select(fixture, shape).expect("plan");

    // Then
    assert_eq!(plan.k_tile_elements(), 16);
    assert_eq!(plan.exsia_slot_bytes(), 8576);
}

#[test]
fn returns_limiting_resource_when_no_tile_fits() {
    // Given
    let mut fixture = GeometryFixture::generous(16);
    fixture.exsia_slot_bytes = 1;

    // When
    let error = select(fixture, MatmulShape::new(16, 16, 32).expect("shape"))
        .expect_err("no ExSIA slot can fit");

    // Then
    assert!(matches!(
        error,
        TilingError::NoFeasibleTile {
            limiting_resource: LimitingResource::ExsiaStripeSlot,
            ..
        }
    ));
}

#[test]
fn exsia_capacity_can_reduce_tile_i() {
    // Given
    let shape = MatmulShape::new(64, 64, 32).expect("shape");
    let generous = GeometryFixture::generous(16);
    let mut limited = generous;
    limited.exsia_slot_bytes = 3000;

    // When
    let generous_plan = select(generous, shape).expect("generous");
    let limited_plan = select(limited, shape).expect("limited");

    // Then
    assert!(generous_plan.factors().i() > limited_plan.factors().i());
    assert_eq!(limited_plan.factors().i(), 1);
}

#[test]
fn last_stripe_is_partial() {
    // Given
    let mut fixture = GeometryFixture::generous(16);
    fixture.exsia_slot_bytes = 4288;
    let plan = select(fixture, MatmulShape::new(33, 64, 32).expect("shape")).expect("plan");

    // When
    let activation = plan.activation_plan().expect("activation plan");

    // Then
    assert_eq!(activation.stripes().last().expect("last").row_count(), 1);
}

#[test]
fn activation_plan_covers_all_rows() {
    // Given
    let shape = MatmulShape::new(191, 768, 768).expect("shape");
    let plan = select(GeometryFixture::generous(32), shape).expect("plan");

    // When
    let activation = plan.activation_plan().expect("activation plan");
    let covered = activation
        .stripes()
        .iter()
        .map(|stripe| stripe.row_count())
        .sum::<usize>();

    // Then
    assert_eq!(covered, shape.m());
    assert_eq!(activation.matrix().k(), shape.k());
}

#[test]
fn supports_dim16() {
    // Given
    let shape = MatmulShape::new(33, 65, 97).expect("shape");

    // When
    let plan = select(GeometryFixture::generous(16), shape).expect("plan");

    // Then
    assert_eq!(plan.geometry().array_dim(), 16);
}

#[test]
fn supports_dim32() {
    // Given
    let shape = MatmulShape::new(33, 65, 97).expect("shape");

    // When
    let plan = select(GeometryFixture::generous(32), shape).expect("plan");

    // Then
    assert_eq!(plan.geometry().array_dim(), 32);
}

#[test]
fn supports_dim64() {
    // Given
    let shape = MatmulShape::new(65, 129, 193).expect("shape");

    // When
    let plan = select(GeometryFixture::generous(64), shape).expect("plan");

    // Then
    assert_eq!(plan.geometry().array_dim(), 64);
}

#[test]
fn k_tile_may_exceed_32() {
    // Given
    let shape = MatmulShape::new(64, 64, 128).expect("shape");

    // When
    let plan = select(GeometryFixture::generous(16), shape).expect("plan");

    // Then
    assert!(plan.k_tile_elements() > 32);
}
