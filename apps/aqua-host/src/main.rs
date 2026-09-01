use aqua_candle::{tensor_to_host, weight_capture_aqua_device};
use aqua_weight::{AquaWeightRegistry, Hp1WeightStats};
use candle_core::quantized::gguf_file::{Content, GgufTypeProfile};
use candle_core::{DType, Device, Tensor};
use std::error::Error;
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

fn main() -> Result<(), Box<dyn Error>> {
    let arguments = std::env::args().skip(1).collect::<Vec<_>>();
    match parse_command(&arguments).map_err(std::io::Error::other)? {
        Command::Smoke => run_smoke(),
        Command::Help => {
            print_help();
            Ok(())
        }
        Command::InspectHp1 { model, compare } => run_inspect_hp1(&model, compare.as_deref()),
    }
}

fn run_smoke() -> Result<(), Box<dyn Error>> {
    let tensor = Tensor::from_vec(
        vec![0.0_f32, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
        (2, 4),
        &Device::Cpu,
    )?
    .to_dtype(DType::BF16)?;

    let source_dtype = tensor.dtype();
    let host = tensor_to_host(&tensor)?;

    println!("AQuA host initialized");
    println!("Candle device: CPU");
    println!("Candle source dtype: {:?}", source_dtype);
    println!("AQuA canonical dtype: {:?}", host.desc.dtype);
    println!("Tensor shape: {:?}", host.desc.shape);
    println!("Element count: {}", host.desc.len);
    Ok(())
}

#[derive(Clone, Debug, Eq, PartialEq)]
enum Command {
    Smoke,
    Help,
    InspectHp1 {
        model: PathBuf,
        compare: Option<PathBuf>,
    },
}

fn parse_command(arguments: &[String]) -> Result<Command, String> {
    match arguments {
        [] => Ok(Command::Smoke),
        [help] if help == "--help" => Ok(Command::Help),
        [command, model] if command == "inspect-hp1" => Ok(Command::InspectHp1 {
            model: PathBuf::from(model),
            compare: None,
        }),
        [command, model, flag, compare] if command == "inspect-hp1" && flag == "--compare" => {
            Ok(Command::InspectHp1 {
                model: PathBuf::from(model),
                compare: Some(PathBuf::from(compare)),
            })
        }
        [command, ..] if command == "inspect-hp1" => {
            Err("usage: aqua-host inspect-hp1 <model.gguf> [--compare <model.gguf>]".to_owned())
        }
        [command, ..] => Err(format!("unexpected command: {command}")),
    }
}

fn print_help() {
    println!("Usage:");
    println!("  aqua-host");
    println!("  aqua-host inspect-hp1 <model.gguf> [--compare <model.gguf>]");
}

struct CapturedModel {
    profile: GgufTypeProfile,
    tensor_count: usize,
    registry: Arc<Mutex<AquaWeightRegistry>>,
}

fn capture_model(path: &Path) -> Result<CapturedModel, Box<dyn Error>> {
    let registry = Arc::new(Mutex::new(AquaWeightRegistry::new()));
    let device = weight_capture_aqua_device(0, Arc::clone(&registry))?;
    let mut file = std::fs::File::open(path)?;
    let content = Content::read(&mut file)?;
    if content.profile != GgufTypeProfile::AquaQ8Hp1 {
        return Err(format!(
            "inspect-hp1 requires profile AquaQ8Hp1, got {:?}",
            content.profile
        )
        .into());
    }
    let mut tensor_names = content.tensor_infos.keys().cloned().collect::<Vec<_>>();
    tensor_names.sort();
    for name in tensor_names {
        content.tensor(&mut file, &name, &device)?;
    }
    Ok(CapturedModel {
        profile: content.profile,
        tensor_count: content.tensor_infos.len(),
        registry,
    })
}

fn print_model_stats(path: &Path, model: &CapturedModel) -> Result<(), Box<dyn Error>> {
    let registry = model
        .registry
        .lock()
        .map_err(|_| std::io::Error::other("AQuA weight registry lock poisoned"))?;
    let stats = Hp1WeightStats::from_registry(&registry)?;
    println!("model={}", path.display());
    println!("profile={:?}", model.profile);
    println!("gguf-tensors={}", model.tensor_count);
    println!("hp1-tensors={}", stats.tensor_count());
    println!("rows={}", stats.row_count());
    println!("blocks={}", stats.block_count());
    println!("zero-blocks={}", stats.zero_block_count());
    println!("nonzero-blocks={}", stats.nonzero_block_count());
    println!("unique-left-shifts={:?}", stats.unique_left_shifts());
    println!("min-left-shift={:?}", stats.min_left_shift());
    println!("max-left-shift={:?}", stats.max_left_shift());
    println!("left-shift-histogram={:?}", stats.left_shift_histogram());
    println!("direct-shift-bits={}", stats.shift_encoding().direct_bits());
    println!(
        "lut-unique-entries={}",
        stats.shift_encoding().unique_count()
    );
    println!("lut-index-bits={}", stats.shift_encoding().lut_index_bits());
    println!(
        "unique-row-scale-exponents={:?}",
        stats.unique_row_scale_exponents()
    );
    println!(
        "min-row-scale-exponent={:?}",
        stats.row_scale_exponent_min()
    );
    println!(
        "max-row-scale-exponent={:?}",
        stats.row_scale_exponent_max()
    );
    println!("row-scale-histogram={:?}", stats.row_scale_histogram());
    println!("all-zero-rows={}", stats.zero_row_count());
    for tensor in stats.tensor_stats() {
        println!(
            "tensor={} role={:?} rows={} K={} blocks={} zero-blocks={} \
             unique-left-shifts={:?} min-left-shift={:?} max-left-shift={:?} \
             row-scale-exponents={:?}",
            tensor.name(),
            tensor.role(),
            tensor.rows(),
            tensor.k(),
            tensor.block_count(),
            tensor.zero_block_count(),
            tensor.unique_left_shifts(),
            tensor.min_left_shift(),
            tensor.max_left_shift(),
            tensor.unique_row_scale_exponents(),
        );
    }
    Ok(())
}

fn run_inspect_hp1(model_path: &Path, compare_path: Option<&Path>) -> Result<(), Box<dyn Error>> {
    let model = capture_model(model_path)?;
    print_model_stats(model_path, &model)?;
    if let Some(compare_path) = compare_path {
        let comparison = capture_model(compare_path)?;
        print_model_stats(compare_path, &comparison)?;
        let left = model
            .registry
            .lock()
            .map_err(|_| std::io::Error::other("AQuA weight registry lock poisoned"))?;
        let right = comparison
            .registry
            .lock()
            .map_err(|_| std::io::Error::other("AQuA weight registry lock poisoned"))?;
        let matching = left
            .iter()
            .filter(|(name, weight)| right.get(name) == Some(*weight))
            .count();
        if matching != left.len() || left.len() != right.len() {
            return Err(format!(
                "canonical HP1 weight mismatch: {matching}/{} match, comparison has {}",
                left.len(),
                right.len()
            )
            .into());
        }
        println!("canonical-weights-exact={matching}/{matching}");
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::{parse_command, Command};
    use candle_core::quantized::{gguf_file, GgmlDType, QTensor};
    use candle_core::{Device, Tensor};
    use std::path::PathBuf;

    #[test]
    fn parses_smoke_and_help_commands() {
        // Given
        let empty = Vec::new();
        let help = vec!["--help".to_owned()];

        // When
        let smoke = parse_command(&empty).expect("smoke");
        let help = parse_command(&help).expect("help");

        // Then
        assert_eq!(smoke, Command::Smoke);
        assert_eq!(help, Command::Help);
    }

    #[test]
    fn parses_inspect_hp1_command() {
        // Given
        let arguments = vec![
            "inspect-hp1".to_owned(),
            "model.gguf".to_owned(),
            "--compare".to_owned(),
            "output.gguf".to_owned(),
        ];

        // When
        let command = parse_command(&arguments).expect("inspect");

        // Then
        assert_eq!(
            command,
            Command::InspectHp1 {
                model: PathBuf::from("model.gguf"),
                compare: Some(PathBuf::from("output.gguf")),
            }
        );
    }

    #[test]
    fn rejects_invalid_inspect_hp1_arguments() {
        // Given
        let missing_model = vec!["inspect-hp1".to_owned()];
        let unknown = vec!["unknown".to_owned()];

        // When
        let missing_error = parse_command(&missing_model).expect_err("missing model");
        let unknown_error = parse_command(&unknown).expect_err("unknown command");

        // Then
        assert!(missing_error.contains("model.gguf"));
        assert!(unknown_error.contains("unexpected command"));
    }

    #[test]
    fn rejects_standard_gguf_inspection() {
        // Given
        let path = std::env::temp_dir().join(format!(
            "aqua-host-standard-profile-{}.gguf",
            std::process::id()
        ));
        let tensor =
            Tensor::from_vec(vec![1.0_f32; 32], (1, 32), &Device::Cpu).expect("source tensor");
        let tensor = QTensor::quantize(&tensor, GgmlDType::F32).expect("F32 QTensor");
        let mut file = std::fs::File::create(&path).expect("temporary GGUF");
        gguf_file::write(&mut file, &[], &[("weight", &tensor)]).expect("write GGUF");
        drop(file);

        // When
        let result = super::capture_model(&path);
        std::fs::remove_file(path).expect("remove temporary GGUF");

        // Then
        let error = match result {
            Ok(_) => panic!("Standard profile must be rejected"),
            Err(error) => error,
        };
        assert!(error.to_string().contains("AquaQ8Hp1"));
    }
}
