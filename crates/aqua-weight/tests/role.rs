use aqua_weight::{classify_matrix_weight, MatrixWeightRole};

#[test]
fn classifies_gpt2_qkv() {
    // Given
    let name = "blk.3.attn_qkv.weight";

    // When
    let role = classify_matrix_weight(name);

    // Then
    assert_eq!(role, MatrixWeightRole::AttentionQkvFused);
}

#[test]
fn classifies_attention_output() {
    // Given
    let name = "blk.3.attn_output.weight";

    // When
    let role = classify_matrix_weight(name);

    // Then
    assert_eq!(role, MatrixWeightRole::AttentionOutput);
}

#[test]
fn classifies_mlp_up() {
    // Given
    let name = "blk.3.ffn_up.weight";

    // When
    let role = classify_matrix_weight(name);

    // Then
    assert_eq!(role, MatrixWeightRole::MlpUp);
}

#[test]
fn classifies_mlp_down() {
    // Given
    let name = "blk.3.ffn_down.weight";

    // When
    let role = classify_matrix_weight(name);

    // Then
    assert_eq!(role, MatrixWeightRole::MlpDown);
}

#[test]
fn classifies_token_embedding() {
    // Given
    let name = "token_embd.weight";

    // When
    let role = classify_matrix_weight(name);

    // Then
    assert_eq!(role, MatrixWeightRole::TokenEmbedding);
}

#[test]
fn classifies_separate_q_k_v() {
    // Given
    let names = [
        ("blk.0.attn_q.weight", MatrixWeightRole::AttentionQuery),
        ("blk.0.attn_k.weight", MatrixWeightRole::AttentionKey),
        ("blk.0.attn_v.weight", MatrixWeightRole::AttentionValue),
    ];

    // When
    let roles = names.map(|(name, _)| classify_matrix_weight(name));

    // Then
    assert_eq!(roles, names.map(|(_, role)| role));
}

#[test]
fn classifies_mlp_gate() {
    // Given
    let name = "blk.3.ffn_gate.weight";

    // When
    let role = classify_matrix_weight(name);

    // Then
    assert_eq!(role, MatrixWeightRole::MlpGate);
}

#[test]
fn unknown_matrix_is_other() {
    // Given
    let name = "custom.projection.weight";

    // When
    let role = classify_matrix_weight(name);

    // Then
    assert_eq!(role, MatrixWeightRole::OtherMatrix);
}
