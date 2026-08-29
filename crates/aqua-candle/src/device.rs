use crate::DenseQOnlyAquaExecutor;
use crate::FixedStripePlanner;
use aqua_exsia::ExsiaConfig;
use candle_core::Device;
use std::{num::NonZeroUsize, sync::Arc};

/// Builds a Candle AQuA CPU-shadow device with dense Q-only matmul execution.
pub fn dense_q_only_aqua_device(
    device_id: usize,
    config: ExsiaConfig,
    rows_per_stripe: NonZeroUsize,
) -> candle_core::Result<Device> {
    let planner = FixedStripePlanner::new(rows_per_stripe);
    let executor = DenseQOnlyAquaExecutor::new(config, planner);
    Device::new_aqua_with_executor(device_id, Arc::new(executor))
}
