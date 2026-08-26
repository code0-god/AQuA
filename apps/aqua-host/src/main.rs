use aqua_candle::{host_to_tensor, tensor_to_host};
use candle_core::{Device, Tensor};
use std::error::Error;

fn main() -> Result<(), Box<dyn Error>> {
    if !handle_argument(std::env::args().nth(1).as_deref()).map_err(std::io::Error::other)? {
        return Ok(());
    }

    let tensor = Tensor::from_vec(
        vec![0.0_f32, 1.0, 2.0, 3.0, 4.0, 5.0, 6.0, 7.0],
        (2, 4),
        &Device::Cpu,
    )?;
    let host = tensor_to_host(&tensor)?;
    let restored = host_to_tensor(&host)?;

    if tensor.flatten_all()?.to_vec1::<f32>()? != restored.flatten_all()?.to_vec1::<f32>()? {
        return Err("Candle tensor round-trip changed values".into());
    }

    println!("AQuA host initialized");
    println!("Candle device: CPU");
    println!("Tensor shape: {:?}", host.desc.shape);
    println!("Tensor dtype: {:?}", host.desc.dtype);
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
