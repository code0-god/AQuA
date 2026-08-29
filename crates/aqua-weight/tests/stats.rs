use aqua_weight::{parse_hp1_matrix_weight, AquaWeightRegistry, Hp1WeightStats, MatrixWeightRole};

fn block(code: i8, shift: i16, scale_bits: u32) -> [u8; 40] {
    let mut raw = [code.to_le_bytes()[0]; 40];
    raw[32..34].copy_from_slice(&shift.to_le_bytes());
    raw[34..36].fill(0);
    raw[36..40].copy_from_slice(&scale_bits.to_le_bytes());
    raw
}

#[test]
fn computes_known_shift_and_row_scale_statistics() {
    // Given
    let mut first_raw = Vec::new();
    first_raw.extend_from_slice(&block(1, 0, 0.25_f32.to_bits()));
    first_raw.extend_from_slice(&block(1, 3, 0.25_f32.to_bits()));
    first_raw.extend_from_slice(&block(1, 5, 0.25_f32.to_bits()));
    let first =
        parse_hp1_matrix_weight("blk.0.attn_qkv.weight", &[1, 96], &first_raw).expect("first");
    let zero = block(0, i16::MIN, 0);
    let second = parse_hp1_matrix_weight("blk.0.ffn_up.weight", &[1, 32], &zero).expect("second");
    let mut registry = AquaWeightRegistry::new();
    registry.insert(first).expect("unique first");
    registry.insert(second).expect("unique second");

    // When
    let stats = Hp1WeightStats::from_registry(&registry).expect("stats");

    // Then
    assert_eq!(stats.tensor_count(), 2);
    assert_eq!(stats.row_count(), 2);
    assert_eq!(stats.block_count(), 4);
    assert_eq!(stats.zero_block_count(), 1);
    assert_eq!(stats.nonzero_block_count(), 3);
    assert_eq!(stats.unique_left_shifts(), &[0, 3, 5]);
    assert_eq!(stats.min_left_shift(), Some(0));
    assert_eq!(stats.max_left_shift(), Some(5));
    assert_eq!(stats.left_shift_histogram().get(&0), Some(&1));
    assert_eq!(stats.left_shift_histogram().get(&3), Some(&1));
    assert_eq!(stats.left_shift_histogram().get(&5), Some(&1));
    assert_eq!(stats.shift_encoding().direct_bits(), 3);
    assert_eq!(stats.shift_encoding().unique_count(), 3);
    assert_eq!(stats.shift_encoding().lut_index_bits(), 2);
    assert_eq!(stats.unique_row_scale_exponents(), &[-2]);
    assert_eq!(stats.row_scale_exponent_min(), Some(-2));
    assert_eq!(stats.row_scale_exponent_max(), Some(-2));
    assert_eq!(stats.row_scale_histogram().get(&-2), Some(&1));
    assert_eq!(stats.zero_row_count(), 1);
    assert_eq!(stats.tensor_stats().len(), 2);
    assert_eq!(
        stats.tensor_stats()[0].role(),
        MatrixWeightRole::AttentionQkvFused
    );
}

#[test]
fn registry_rejects_duplicate_tensor_name() {
    // Given
    let raw = block(1, 0, 1.0_f32.to_bits());
    let first = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect("first");
    let duplicate = parse_hp1_matrix_weight("weight", &[1, 32], &raw).expect("duplicate");
    let mut registry = AquaWeightRegistry::new();
    registry.insert(first).expect("unique first");

    // When
    let result = registry.insert(duplicate);

    // Then
    assert!(result.is_err());
    assert_eq!(registry.len(), 1);
}
