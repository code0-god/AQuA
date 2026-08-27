//! Software-side ExsIA contract and canonical reference implementation.
//!
//! This crate owns ExSIA-specific semantics.
//! It is independent of Candle, transport, and BSV implementation details.

mod config;
mod error;
mod input;
mod reference;

pub use config::{ExsiaConfig, ExsiaPrecision, EXSIA_BLOCK_SIZE};
pub use error::ExsiaError;
pub use input::ExsiaInput;
pub use reference::ReferenceExsia;
