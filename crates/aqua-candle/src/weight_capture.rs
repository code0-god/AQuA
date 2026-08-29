use aqua_weight::{parse_hp1_matrix_weight, AquaWeightRegistry};
use candle_core::quantized::{gguf_file::GgufTypeProfile, GgmlDType};
use candle_core::{AquaExecutor, AquaGgufTensorRequest, Device, Error, Result};
use std::sync::{Arc, Mutex};

#[derive(Debug)]
pub struct WeightCaptureAquaExecutor {
    registry: Arc<Mutex<AquaWeightRegistry>>,
}

impl WeightCaptureAquaExecutor {
    pub fn new(registry: Arc<Mutex<AquaWeightRegistry>>) -> Self {
        Self { registry }
    }
}

impl AquaExecutor for WeightCaptureAquaExecutor {
    fn name(&self) -> &'static str {
        "weight-capture"
    }

    fn prepare_gguf_tensor(&self, request: AquaGgufTensorRequest<'_>) -> Result<()> {
        if request.profile() != GgufTypeProfile::AquaQ8Hp1 || request.dtype() != GgmlDType::Q8HP1 {
            return Ok(());
        }
        let weight =
            parse_hp1_matrix_weight(request.name(), request.shape().dims(), request.raw_data())
                .map_err(|error| Error::Msg(error.to_string()))?;
        self.registry
            .lock()
            .map_err(|_| Error::Msg("AQuA weight registry lock poisoned".to_owned()))?
            .insert(weight)
            .map_err(|error| Error::Msg(error.to_string()))
    }
}

pub fn weight_capture_aqua_device(
    device_id: usize,
    registry: Arc<Mutex<AquaWeightRegistry>>,
) -> Result<Device> {
    let executor: Arc<dyn AquaExecutor> = Arc::new(WeightCaptureAquaExecutor::new(registry));
    Device::new_aqua_with_executor(device_id, executor)
}
