use crate::{DenseWeightCodes, RacoError};
use aqua_exsia::ResidualStripe;

pub(super) fn direct_correction(
    residuals: &ResidualStripe,
    weights: &DenseWeightCodes<'_>,
) -> Result<Vec<i64>, RacoError> {
    if residuals.logical_k() != weights.logical_k() {
        return Err(RacoError::WeightKDoesNotMatch {
            residual_k: residuals.logical_k(),
            weight_k: weights.logical_k(),
        });
    }
    let len = residuals
        .row_count()
        .checked_mul(weights.logical_j())
        .ok_or(RacoError::ElementCountOverflow {
            field: "direct correction",
        })?;
    let mut accumulators = vec![0_i128; len];

    for event in residuals.iter() {
        if event.local_row() >= residuals.row_count() {
            return Err(RacoError::ResidualRowOutOfBounds {
                local_row: event.local_row(),
                row_count: residuals.row_count(),
            });
        }
        if event.k() >= residuals.logical_k() {
            return Err(RacoError::ResidualKOutOfBounds {
                k: event.k(),
                logical_k: residuals.logical_k(),
            });
        }
        for j in 0..weights.logical_j() {
            let index = event
                .local_row()
                .checked_mul(weights.logical_j())
                .and_then(|value| value.checked_add(j))
                .ok_or(RacoError::ElementCountOverflow {
                    field: "direct correction index",
                })?;
            accumulators[index] +=
                i128::from(event.residual()) * i128::from(weights.value(event.k(), j)?);
        }
    }

    accumulators
        .into_iter()
        .enumerate()
        .map(|(index, value)| {
            i64::try_from(value).map_err(|_| RacoError::CorrectionOverflow {
                local_row: index / weights.logical_j(),
                j: index % weights.logical_j(),
            })
        })
        .collect()
}
