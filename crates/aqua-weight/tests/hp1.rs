use aqua_weight::{
    parse_h1_matrix_weight, parse_hp1_matrix_weight, Hp1BlockScale, MatrixWeightRole, WeightError,
    HP1_BLOCK_BYTES,
};

fn block(codes: [i8; 32], shift: i16, padding: [u8; 2], scale_bits: u32) -> [u8; 40] {
    let mut raw = [0_u8; 40];
    for (slot, code) in raw[..32].iter_mut().zip(codes) {
        *slot = code.to_le_bytes()[0];
    }
    raw[32..34].copy_from_slice(&shift.to_le_bytes());
    raw[34..36].copy_from_slice(&padding);
    raw[36..40].copy_from_slice(&scale_bits.to_le_bytes());
    raw
}

#[test]
fn parses_one_hp1_block() {
    // Given
    let raw = block([1; 32], 3, [0, 0], 0.25_f32.to_bits());

    // When
    let weight = parse_hp1_matrix_weight("blk.0.attn_q.weight", &[1, 32], &raw).expect("valid HP1");

    // Then
    assert_eq!(weight.descriptor().name(), "blk.0.attn_q.weight");
    assert_eq!(weight.descriptor().role(), MatrixWeightRole::AttentionQuery);
    assert_eq!(weight.descriptor().shape().rows(), 1);
    assert_eq!(weight.descriptor().shape().k(), 32);
    assert_eq!(weight.codes(), &[1; 32]);
    assert_eq!(weight.block_scales(), &[Hp1BlockScale::LeftShift(3)]);
    assert_eq!(weight.row_scales()[0].bits(), 0.25_f32.to_bits());
    assert_eq!(weight.row_scales()[0].exponent(), Some(-2));
}

#[test]
fn parses_multiple_blocks_in_one_row() {
    // Given
    let mut raw = Vec::new();
    raw.extend_from_slice(&block([1; 32], 0, [0, 0], 0.5_f32.to_bits()));
    raw.extend_from_slice(&block([-2; 32], 4, [0, 0], 0.5_f32.to_bits()));

    // When
    let weight = parse_hp1_matrix_weight("output.weight", &[1, 64], &raw).expect("valid HP1");

    // Then
    assert_eq!(weight.codes().len(), 64);
    assert_eq!(
        weight.block_scales(),
        &[Hp1BlockScale::LeftShift(0), Hp1BlockScale::LeftShift(4)]
    );
}

#[test]
fn parses_multiple_rows() {
    // Given
    let mut raw = Vec::new();
    raw.extend_from_slice(&block([1; 32], 0, [0, 0], 0.5_f32.to_bits()));
    raw.extend_from_slice(&block([2; 32], 1, [0, 0], 0.125_f32.to_bits()));

    // When
    let weight = parse_hp1_matrix_weight("blk.0.ffn_up.weight", &[2, 32], &raw).expect("valid HP1");

    // Then
    assert_eq!(weight.descriptor().shape().rows(), 2);
    assert_eq!(weight.row_scales()[0].exponent(), Some(-1));
    assert_eq!(weight.row_scales()[1].exponent(), Some(-3));
}

#[test]
fn extracts_integer_codes() {
    // Given
    let mut codes = [0_i8; 32];
    codes[0] = -127;
    codes[31] = i8::MAX;
    let raw = block(codes, 0, [0, 0], 1.0_f32.to_bits());

    // When
    let weight = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect("valid HP1");

    // Then
    assert_eq!(weight.codes()[0], -127);
    assert_eq!(weight.codes()[31], i8::MAX);
}

#[test]
fn rejects_i8_min_code() {
    // Given
    let mut codes = [0_i8; 32];
    codes[7] = i8::MIN;
    let raw = block(codes, 0, [0, 0], 1.0_f32.to_bits());

    // When
    let error = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect_err("invalid code");

    // Then
    assert!(matches!(error, WeightError::InvalidCode { index: 7, .. }));
}

#[test]
fn rejects_effective_block_scale_overflow() {
    // Given
    let maximum_power_of_two = f32::from_bits(0x7f00_0000);
    let raw = block([1; 32], 1, [0, 0], maximum_power_of_two.to_bits());

    // When
    let error =
        parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect_err("effective scale overflow");

    // Then
    assert!(matches!(
        error,
        WeightError::InvalidEffectiveBlockScale { .. }
    ));
}

#[test]
fn maps_positive_m_to_left_shift() {
    // Given
    let raw = block([1; 32], 17, [0, 0], 1.0_f32.to_bits());

    // When
    let weight = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect("valid HP1");

    // Then
    assert_eq!(weight.block_scales(), &[Hp1BlockScale::LeftShift(17)]);
}

#[test]
fn maps_i16_min_to_zero_block() {
    // Given
    let raw = block([0; 32], i16::MIN, [0, 0], 0);

    // When
    let weight = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect("zero HP1 row");

    // Then
    assert_eq!(weight.block_scales(), &[Hp1BlockScale::ZeroBlock]);
    assert_eq!(weight.row_scales()[0].exponent(), None);
}

#[test]
fn preserves_all_zero_codes_in_nonzero_block() {
    // Given
    let raw = block([0; 32], 2, [0, 0], 1.0_f32.to_bits());

    // When
    let weight = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect("valid HP1");

    // Then
    assert_eq!(weight.block_scales(), &[Hp1BlockScale::LeftShift(2)]);
}

#[test]
fn rejects_negative_non_sentinel_m() {
    // Given
    let raw = block([1; 32], -1, [0, 0], 1.0_f32.to_bits());

    // When
    let error = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect_err("negative shift");

    // Then
    assert!(matches!(error, WeightError::NegativeBlockShift { .. }));
}

#[test]
fn rejects_nonzero_zero_block_codes() {
    // Given
    let raw = block([1; 32], i16::MIN, [0, 0], 0);

    // When
    let error = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect_err("bad zero block");

    // Then
    assert!(matches!(
        error,
        WeightError::InvalidZeroBlockEncoding { .. }
    ));
}

#[test]
fn rejects_nonzero_padding() {
    // Given
    let raw = block([1; 32], 0, [1, 0], 1.0_f32.to_bits());

    // When
    let error = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect_err("bad padding");

    // Then
    assert!(matches!(error, WeightError::NonzeroPadding { .. }));
}

#[test]
fn rejects_inconsistent_row_channel_scale() {
    // Given
    let mut raw = Vec::new();
    raw.extend_from_slice(&block([1; 32], 0, [0, 0], 1.0_f32.to_bits()));
    raw.extend_from_slice(&block([1; 32], 0, [0, 0], 0.5_f32.to_bits()));

    // When
    let error =
        parse_hp1_matrix_weight("weight", &[1, 64], &raw).expect_err("inconsistent row scale");

    // Then
    assert!(matches!(error, WeightError::InconsistentRowScale { .. }));
}

#[test]
fn rejects_non_power_of_two_channel_scale() {
    // Given
    let raw = block([1; 32], 0, [0, 0], 1.5_f32.to_bits());

    // When
    let error = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect_err("invalid scale");

    // Then
    assert!(matches!(error, WeightError::InvalidRowScale { .. }));
}

#[test]
fn accepts_subnormal_power_of_two_channel_scale() {
    // Given
    let bits = 1_u32 << 7;
    let raw = block([1; 32], 0, [0, 0], bits);

    // When
    let weight = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect("subnormal scale");

    // Then
    assert_eq!(weight.row_scales()[0].exponent(), Some(-142));
}

#[test]
fn accepts_all_zero_row() {
    // Given
    let mut raw = Vec::new();
    raw.extend_from_slice(&block([0; 32], i16::MIN, [0, 0], 0));
    raw.extend_from_slice(&block([0; 32], i16::MIN, [0, 0], 0));

    // When
    let weight = parse_hp1_matrix_weight("weight", &[1, 64], &raw).expect("zero row");

    // Then
    assert!(weight.row_scales()[0].exponent().is_none());
}

#[test]
fn rejects_wrong_payload_length() {
    // Given
    let raw = vec![0_u8; HP1_BLOCK_BYTES - 1];

    // When
    let error = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect_err("short payload");

    // Then
    assert!(matches!(error, WeightError::PayloadLengthMismatch { .. }));
}

#[test]
fn rejects_k_not_divisible_by_32() {
    // Given
    let raw = vec![0_u8; HP1_BLOCK_BYTES];

    // When
    let error = parse_hp1_matrix_weight("weight", &[1, 33], &raw).expect_err("unaligned K");

    // Then
    assert!(matches!(error, WeightError::KNotBlockAligned { .. }));
}

#[test]
fn rejects_h1_canonical_extraction() {
    // Given
    let raw = vec![0_u8; 44];

    // When
    let error = parse_h1_matrix_weight("weight", &[1, 32], &raw).expect_err("unsupported H1");

    // Then
    assert_eq!(error, WeightError::UnsupportedQ8H1);
}
