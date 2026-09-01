//! Candle adapter and dense Q-only AQuA integration.

mod adapter;
mod device;
mod executor;
mod planner;
mod weight_capture;

pub use adapter::{host_to_tensor, host_to_tensor_on, tensor_to_host, AdapterError};
pub use device::dense_q_only_aqua_device;
pub use executor::DenseQOnlyAquaExecutor;
pub use planner::FixedStripePlanner;
pub use weight_capture::{weight_capture_aqua_device, WeightCaptureAquaExecutor};
