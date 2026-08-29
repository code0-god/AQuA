//! Candle-independent canonical AQuA weight contracts.

mod descriptor;
mod error;
mod hp1;
mod registry;
mod role;
mod stats;

pub use descriptor::{MatrixWeightDescriptor, MatrixWeightShape};
pub use error::WeightError;
pub use hp1::{
    parse_h1_matrix_weight, parse_hp1_matrix_weight, Hp1BlockScale, Hp1MatrixWeight, Hp1RowScale,
    HP1_BLOCK_BYTES,
};
pub use registry::AquaWeightRegistry;
pub use role::{classify_matrix_weight, MatrixWeightRole};
pub use stats::{Hp1TensorStats, Hp1WeightStats, ShiftEncodingStats};
