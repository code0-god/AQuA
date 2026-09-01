use aqua_candle::weight_capture_aqua_device;
use aqua_weight::{AquaWeightRegistry, Hp1BlockScale, MatrixWeightRole};
use candle_core::quantized::{
    gguf_file::{self, Value},
    GgmlDType, QTensor,
};
use candle_core::{Device, Result, Tensor};
use std::io::Cursor;
use std::sync::{Arc, Mutex};

fn gguf(dtype: GgmlDType, metadata: &[(&str, Value)]) -> Result<Cursor<Vec<u8>>> {
    let source = Tensor::from_vec(vec![1.0_f32; 32], (1, 32), &Device::Cpu)?;
    let source = QTensor::quantize(&source, dtype)?;
    let metadata = metadata
        .iter()
        .map(|(key, value)| (*key, value))
        .collect::<Vec<_>>();
    let mut cursor = Cursor::new(Vec::new());
    gguf_file::write(&mut cursor, &metadata, &[("blk.0.attn_q.weight", &source)])?;
    cursor.set_position(0);
    Ok(cursor)
}

fn hp1_metadata() -> Vec<(&'static str, Value)> {
    vec![
        ("aqua.gguf.profile", Value::String("q8_hp1".to_owned())),
        ("aqua.gguf.profile_version", Value::U32(1)),
        ("general.quantization_version", Value::U32(2)),
        ("general.file_type", Value::U32(40)),
    ]
}

#[test]
fn captures_hp1_weight_during_gguf_materialization() -> Result<()> {
    // Given
    let registry = Arc::new(Mutex::new(AquaWeightRegistry::new()));
    let device = weight_capture_aqua_device(0, Arc::clone(&registry))?;
    let mut cursor = gguf(GgmlDType::Q8HP1, &hp1_metadata())?;
    let content = gguf_file::Content::read(&mut cursor)?;

    // When
    let loaded = content.tensor(&mut cursor, "blk.0.attn_q.weight", &device)?;

    // Then
    assert!(loaded.device().is_cpu());
    let registry = registry.lock().expect("registry lock");
    let weight = registry
        .get("blk.0.attn_q.weight")
        .expect("captured weight");
    assert_eq!(weight.descriptor().role(), MatrixWeightRole::AttentionQuery);
    assert_eq!(weight.descriptor().shape().rows(), 1);
    assert_eq!(weight.descriptor().shape().k(), 32);
    assert_eq!(weight.codes(), &[64; 32]);
    assert_eq!(weight.block_scales(), &[Hp1BlockScale::LeftShift(0)]);
    assert_eq!(weight.row_scales()[0].exponent(), Some(-6));
    Ok(())
}

#[test]
fn ignores_non_hp1_gguf_tensors() -> Result<()> {
    // Given
    let registry = Arc::new(Mutex::new(AquaWeightRegistry::new()));
    let device = weight_capture_aqua_device(0, Arc::clone(&registry))?;
    let mut cursor = gguf(GgmlDType::F32, &[])?;
    let content = gguf_file::Content::read(&mut cursor)?;

    // When
    let loaded = content.tensor(&mut cursor, "blk.0.attn_q.weight", &device)?;

    // Then
    assert!(loaded.device().is_cpu());
    assert!(registry.lock().expect("registry lock").is_empty());
    Ok(())
}

#[test]
fn ignores_q8_h1_until_canonical_extraction_exists() -> Result<()> {
    // Given
    let metadata = [
        ("aqua.gguf.profile", Value::String("q8_h1".to_owned())),
        ("aqua.gguf.profile_version", Value::U32(1)),
        ("general.quantization_version", Value::U32(2)),
        ("general.file_type", Value::U32(38)),
    ];
    let registry = Arc::new(Mutex::new(AquaWeightRegistry::new()));
    let device = weight_capture_aqua_device(0, Arc::clone(&registry))?;
    let mut cursor = gguf(GgmlDType::Q8H1, &metadata)?;
    let content = gguf_file::Content::read(&mut cursor)?;

    // When
    let loaded = content.tensor(&mut cursor, "blk.0.attn_q.weight", &device)?;

    // Then
    assert!(loaded.device().is_cpu());
    assert!(registry.lock().expect("registry lock").is_empty());
    Ok(())
}
