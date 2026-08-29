use super::super::{block::BlockResult, math};
use super::fold_stripe;
use crate::{ExsiaConfig, ExsiaError, ExsiaPrecision, QuantizedValues, ResidualEvent};
use aqua_runtime::StripePlan;

fn block(wide: Vec<i32>, exponent: i16, outlier_mask: u32) -> BlockResult {
    BlockResult {
        wide,
        exponent,
        outlier_mask,
    }
}

const fn config(precision: ExsiaPrecision) -> ExsiaConfig {
    ExsiaConfig::new(precision)
}

const fn stripe(stripe_index: usize, row_start: usize, row_end: usize) -> StripePlan {
    StripePlan::new(stripe_index, row_start, row_end)
}

#[path = "contract_tests/layout.rs"]
mod layout;
#[path = "contract_tests/semantics.rs"]
mod semantics;
