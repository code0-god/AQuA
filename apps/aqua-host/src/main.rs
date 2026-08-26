use aqua_candle::{host_to_tensor, tensor_to_host};
use candle_core::{Device, Tensor, DType};
use std::error::Error;

fn main() -> Result<(), Box<dyn Error>> {
    if !handle_argument(std::env::args().nth(1).as_deref()).map_err(std::io::Error::other)? {
        return Ok(());
    }

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

fn handle_argument(argument: Option<&str>) -> Result<bool, String> {
    match argument {
        None => Ok(true),
        Some("--help") => {
            println!("Usage: aqua-host");
            Ok(false)
        }
        Some(argument) => Err(format!("unexpected argument: {argument}")),
    }
}

#[cfg(test)]
mod tests {
    use super::handle_argument;

    #[test]
    fn accepts_only_help_argument() {
        assert!(handle_argument(None).expect("no argument should run smoke test"));
        assert!(!handle_argument(Some("--help")).expect("help should exit successfully"));
        assert_eq!(
            handle_argument(Some("--unknown")),
            Err("unexpected argument: --unknown".to_string())
        );
    }
}
