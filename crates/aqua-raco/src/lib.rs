//! Canonical RaCo functional reference for future BSV implementation.
//!
//! This crate defines deterministic integer-domain semantics for residual
//! radix decomposition, block/K compaction, lane execution, and correction
//! composition.

mod builder;
mod compose;
mod contract;
mod error;
mod execute;
mod radix;
mod reference;

pub use builder::build_stripe_work;
pub use compose::{compose_correction, RawRacoCorrection};
pub use contract::{
    RacoBlockOutput, RacoBlockWork, RacoCompressedOutput, RacoDigitValues, RacoStripeWork,
};
pub use error::RacoError;
pub use execute::{execute_integer_reference, DenseWeightCodes};
pub use radix::{
    compose_digits, decompose_residual, radix_contract, BalancedDigits, RadixContract,
    RACO_MAX_LANES, RACO_RESIDUAL_BITS, RACO_RESIDUAL_MAX, RACO_RESIDUAL_MIN,
};
pub use reference::{execute_raco_reference, RacoReferenceResult};
