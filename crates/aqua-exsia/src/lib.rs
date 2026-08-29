//! Software-side ExsIA contract and canonical reference implementation.
//!
//! This crate owns ExSIA-specific semantics.
//! It is independent of Candle, transport, and BSV implementation details.

mod algorithm;
mod config;
mod error;
mod input;
mod output;
mod reference;
mod residual;

pub use config::{ExsiaConfig, ExsiaPrecision, EXSIA_BLOCK_SIZE};
pub use error::ExsiaError;
pub use input::ExsiaInput;
pub use output::{ExsiaOutput, QuantizedValues};
pub use reference::ReferenceExsia;
pub use residual::{ResidualEvent, ResidualStripe};
