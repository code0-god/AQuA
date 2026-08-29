use super::ReferenceExsia;
use crate::{ExsiaConfig, ExsiaError, ExsiaInput, ExsiaOutput, ExsiaPrecision, QuantizedValues};
use aqua_runtime::{
    ActivationExecutionPlan, ActivationMatrixShape, ExecutionPlanError, HostTensor, StripePlan,
};

fn host_tensor(shape: &[usize], values: Vec<f32>) -> HostTensor {
    HostTensor::f32(shape.to_vec(), values).expect("valid host tensor")
}

fn execution_plan(shape: &[usize], row_ranges: &[(usize, usize)]) -> ActivationExecutionPlan {
    let matrix = ActivationMatrixShape::from_tensor_shape(shape).expect("valid matrix shape");
    let stripes = row_ranges
        .iter()
        .copied()
        .enumerate()
        .map(|(index, (row_start, row_end))| StripePlan::new(index, row_start, row_end))
        .collect();

    ActivationExecutionPlan::new(matrix, stripes).expect("valid execution plan")
}

fn execute_with_plan(
    tensor: &HostTensor,
    precision: ExsiaPrecision,
    plan: &ActivationExecutionPlan,
) -> ExsiaOutput {
    let input = ExsiaInput::new(tensor, ExsiaConfig::new(precision)).expect("valid ExSIA input");

    ReferenceExsia::new()
        .execute(&input, plan)
        .expect("reference execution")
}

fn execute(
    shape: &[usize],
    values: Vec<f32>,
    precision: ExsiaPrecision,
    row_ranges: &[(usize, usize)],
) -> ExsiaOutput {
    let tensor = host_tensor(shape, values);
    let plan = execution_plan(shape, row_ranges);

    execute_with_plan(&tensor, precision, &plan)
}

fn repeated_rows(row_values: &[f32], logical_k: usize) -> Vec<f32> {
    let mut values = Vec::with_capacity(row_values.len() * logical_k);

    for &value in row_values {
        values.resize(values.len() + logical_k, value);
    }

    values
}

#[path = "contract_tests/layout.rs"]
mod layout;
#[path = "contract_tests/semantics.rs"]
mod semantics;
