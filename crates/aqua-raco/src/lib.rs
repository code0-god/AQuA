//! Canonical RaCo functional reference for future BSV implementation.
//!
//! This crate defines deterministic integer-domain semantics for residual
//! radix decomposition and block/K compaction.

mod builder;
mod contract;
mod error;
mod radix;

pub use builder::build_stripe_work;
pub use contract::{
    RacoBlockOutput, RacoBlockWork, RacoCompressedOutput, RacoDigitValues, RacoStripeWork,
};
pub use error::RacoError;
pub use radix::{
    compose_digits, decompose_residual, radix_contract, BalancedDigits, RadixContract,
    RACO_MAX_LANES, RACO_RESIDUAL_BITS, RACO_RESIDUAL_MAX, RACO_RESIDUAL_MIN,
};
