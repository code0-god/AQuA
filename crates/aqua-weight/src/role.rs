#[derive(Clone, Copy, Debug, Eq, Ord, PartialEq, PartialOrd)]
pub enum MatrixWeightRole {
    TokenEmbedding,
    AttentionQuery,
    AttentionKey,
    AttentionValue,
    AttentionQkvFused,
    AttentionOutput,
    MlpGate,
    MlpUp,
    MlpDown,
    LmHead,
    OtherMatrix,
}

pub fn classify_matrix_weight(name: &str) -> MatrixWeightRole {
    if matches!(name, "token_embd.weight" | "tok_embeddings.weight") {
        return MatrixWeightRole::TokenEmbedding;
    }
    if name == "output.weight" {
        return MatrixWeightRole::LmHead;
    }
    if name.ends_with(".attn_qkv.weight") {
        return MatrixWeightRole::AttentionQkvFused;
    }
    if name.ends_with(".attn_q.weight") {
        return MatrixWeightRole::AttentionQuery;
    }
    if name.ends_with(".attn_k.weight") {
        return MatrixWeightRole::AttentionKey;
    }
    if name.ends_with(".attn_v.weight") {
        return MatrixWeightRole::AttentionValue;
    }
    if name.ends_with(".attn_output.weight") {
        return MatrixWeightRole::AttentionOutput;
    }
    if name.ends_with(".ffn_gate.weight") {
        return MatrixWeightRole::MlpGate;
    }
    if name.ends_with(".ffn_up.weight") {
        return MatrixWeightRole::MlpUp;
    }
    if name.ends_with(".ffn_down.weight") {
        return MatrixWeightRole::MlpDown;
    }
    MatrixWeightRole::OtherMatrix
}
