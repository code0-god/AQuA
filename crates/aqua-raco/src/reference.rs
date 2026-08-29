use crate::{
    build_stripe_work, compose_correction, execute_integer_reference, DenseWeightCodes,
    RacoCompressedOutput, RacoError, RacoStripeWork, RawRacoCorrection,
};
use aqua_exsia::{ExsiaPrecision, ResidualStripe};

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct RacoReferenceResult {
    work: Option<RacoStripeWork>,
    compressed: Option<RacoCompressedOutput>,
    correction: RawRacoCorrection,
}

impl RacoReferenceResult {
    pub const fn work(&self) -> Option<&RacoStripeWork> {
        self.work.as_ref()
    }

    pub const fn compressed(&self) -> Option<&RacoCompressedOutput> {
        self.compressed.as_ref()
    }

    pub const fn correction(&self) -> &RawRacoCorrection {
        &self.correction
    }
}

pub fn execute_raco_reference(
    residuals: &ResidualStripe,
    precision: ExsiaPrecision,
    weights: &DenseWeightCodes<'_>,
) -> Result<RacoReferenceResult, RacoError> {
    if residuals.logical_k() != weights.logical_k() {
        return Err(RacoError::WeightKDoesNotMatch {
            residual_k: residuals.logical_k(),
            weight_k: weights.logical_k(),
        });
    }

    let work = build_stripe_work(residuals, precision)?;
    let Some(work) = work else {
        let correction_len = residuals
            .row_count()
            .checked_mul(weights.logical_j())
            .ok_or(RacoError::ElementCountOverflow {
                field: "empty correction",
            })?;
        return Ok(RacoReferenceResult {
            work: None,
            compressed: None,
            correction: RawRacoCorrection {
                stripe_index: u32_field("stripe index", residuals.stripe_index())?,
                row_start: u32_field("row start", residuals.row_start())?,
                row_count: u32_field("row count", residuals.row_count())?,
                logical_j: u32_field("logical J", weights.logical_j())?,
                values: vec![0; correction_len],
            },
        });
    };

    let compressed = execute_integer_reference(&work, weights)?;
    let correction = compose_correction(&work, &compressed)?;

    Ok(RacoReferenceResult {
        work: Some(work),
        compressed: Some(compressed),
        correction,
    })
}

fn u32_field(field: &'static str, value: usize) -> Result<u32, RacoError> {
    u32::try_from(value).map_err(|_| RacoError::IndexDoesNotFitU32 { field, value })
}

#[cfg(test)]
mod oracle;
#[cfg(test)]
mod tests;
