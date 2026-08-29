use super::{ActivationExecutionPlan, ActivationMatrixShape, ExecutionPlanError, StripePlan};

fn matrix(rows: usize, k: usize) -> ActivationMatrixShape {
    ActivationMatrixShape::from_tensor_shape(&[rows, k]).expect("valid matrix shape")
}

#[test]
fn matrix_shape_from_rank_one() {
    // Given
    let tensor_shape = [4096];

    // When
    let shape =
        ActivationMatrixShape::from_tensor_shape(&tensor_shape).expect("valid rank-one shape");

    // Then
    assert_eq!(shape.rows(), 1);
    assert_eq!(shape.k(), 4096);
    assert_eq!(shape.element_count(), Ok(4096));
}

#[test]
fn matrix_shape_flattens_leading_dimensions() {
    // Given
    let tensor_shape = [2, 3, 4];

    // When
    let shape =
        ActivationMatrixShape::from_tensor_shape(&tensor_shape).expect("valid tensor shape");

    // Then
    assert_eq!(shape.rows(), 6);
    assert_eq!(shape.k(), 4);
    assert_eq!(shape.element_count(), Ok(24));
}

#[test]
fn matrix_shape_rejects_empty_shape() {
    // Given
    let tensor_shape = [];

    // When
    let result = ActivationMatrixShape::from_tensor_shape(&tensor_shape);

    // Then
    assert_eq!(result, Err(ExecutionPlanError::EmptyTensorShape));
}

#[test]
fn matrix_shape_rejects_zero_k() {
    // Given
    let tensor_shape = [2, 0];

    // When
    let result = ActivationMatrixShape::from_tensor_shape(&tensor_shape);

    // Then
    assert_eq!(result, Err(ExecutionPlanError::ZeroK));
}

#[test]
fn matrix_shape_rejects_zero_rows() {
    // Given
    let tensor_shape = [2, 0, 4];

    // When
    let result = ActivationMatrixShape::from_tensor_shape(&tensor_shape);

    // Then
    assert_eq!(result, Err(ExecutionPlanError::ZeroRows));
}

#[test]
fn matrix_shape_rejects_overflow() {
    // Given
    let tensor_shape = [usize::MAX, 2];

    // When
    let result = ActivationMatrixShape::from_tensor_shape(&tensor_shape);

    // Then
    assert_eq!(result, Err(ExecutionPlanError::ElementCountOverflow));
}

#[test]
fn stripe_plan_reports_range_metadata() {
    // Given
    let stripe = StripePlan::new(3, 8, 10);

    // When
    let metadata = (
        stripe.stripe_index(),
        stripe.row_start(),
        stripe.row_end(),
        stripe.row_count(),
        stripe.is_empty(),
    );

    // Then
    assert_eq!(metadata, (3, 8, 10, 2, false));
}

#[test]
fn accepts_contiguous_stripes() {
    // Given
    let stripes = vec![
        StripePlan::new(0, 0, 4),
        StripePlan::new(1, 4, 8),
        StripePlan::new(2, 8, 10),
    ];

    // When
    let plan =
        ActivationExecutionPlan::new(matrix(10, 32), stripes).expect("contiguous stripe plan");

    // Then
    assert_eq!(plan.matrix(), matrix(10, 32));
    assert_eq!(plan.stripe_count(), 3);
    assert_eq!(
        plan.stripes(),
        &[
            StripePlan::new(0, 0, 4),
            StripePlan::new(1, 4, 8),
            StripePlan::new(2, 8, 10),
        ]
    );
}

#[test]
fn rejects_empty_stripe_plan() {
    // Given
    let stripes = Vec::new();

    // When
    let result = ActivationExecutionPlan::new(matrix(10, 32), stripes);

    // Then
    assert_eq!(result, Err(ExecutionPlanError::EmptyStripePlan));
}

#[test]
fn rejects_empty_stripe() {
    // Given
    let stripes = vec![
        StripePlan::new(0, 0, 4),
        StripePlan::new(1, 4, 4),
        StripePlan::new(2, 4, 10),
    ];

    // When
    let result = ActivationExecutionPlan::new(matrix(10, 32), stripes);

    // Then
    assert_eq!(
        result,
        Err(ExecutionPlanError::EmptyStripe {
            stripe_index: 1,
            row_start: 4,
            row_end: 4,
        })
    );
}

#[test]
fn rejects_wrong_stripe_index() {
    // Given
    let stripes = vec![StripePlan::new(0, 0, 4), StripePlan::new(2, 4, 10)];

    // When
    let result = ActivationExecutionPlan::new(matrix(10, 32), stripes);

    // Then
    assert_eq!(
        result,
        Err(ExecutionPlanError::InvalidStripeIndex {
            expected: 1,
            actual: 2,
        })
    );
}

#[test]
fn rejects_missing_initial_rows() {
    // Given
    let stripes = vec![StripePlan::new(0, 1, 10)];

    // When
    let result = ActivationExecutionPlan::new(matrix(10, 32), stripes);

    // Then
    assert_eq!(
        result,
        Err(ExecutionPlanError::StripeGap {
            previous_end: 0,
            next_start: 1,
        })
    );
}

#[test]
fn rejects_stripe_gap() {
    // Given
    let stripes = vec![StripePlan::new(0, 0, 4), StripePlan::new(1, 5, 10)];

    // When
    let result = ActivationExecutionPlan::new(matrix(10, 32), stripes);

    // Then
    assert_eq!(
        result,
        Err(ExecutionPlanError::StripeGap {
            previous_end: 4,
            next_start: 5,
        })
    );
}

#[test]
fn rejects_stripe_overlap() {
    // Given
    let stripes = vec![StripePlan::new(0, 0, 6), StripePlan::new(1, 4, 10)];

    // When
    let result = ActivationExecutionPlan::new(matrix(10, 32), stripes);

    // Then
    assert_eq!(
        result,
        Err(ExecutionPlanError::StripeOverlap {
            previous_end: 6,
            next_start: 4,
        })
    );
}

#[test]
fn rejects_out_of_bounds_stripe() {
    // Given
    let stripes = vec![StripePlan::new(0, 0, 11)];

    // When
    let result = ActivationExecutionPlan::new(matrix(10, 32), stripes);

    // Then
    assert_eq!(
        result,
        Err(ExecutionPlanError::StripeOutOfBounds {
            stripe_index: 0,
            row_end: 11,
            rows: 10,
        })
    );
}

#[test]
fn rejects_incomplete_coverage() {
    // Given
    let stripes = vec![StripePlan::new(0, 0, 9)];

    // When
    let result = ActivationExecutionPlan::new(matrix(10, 32), stripes);

    // Then
    assert_eq!(
        result,
        Err(ExecutionPlanError::IncompleteRowCoverage {
            covered_until: 9,
            rows: 10,
        })
    );
}

#[test]
fn validates_matching_tensor_shape() {
    // Given
    let plan = ActivationExecutionPlan::new(
        matrix(6, 4),
        vec![StripePlan::new(0, 0, 3), StripePlan::new(1, 3, 6)],
    )
    .expect("valid plan");

    // When
    let result = plan.validate_tensor_shape(&[2, 3, 4]);

    // Then
    assert_eq!(result, Ok(()));
}

#[test]
fn rejects_mismatched_tensor_shape() {
    // Given
    let plan = ActivationExecutionPlan::new(
        matrix(6, 4),
        vec![StripePlan::new(0, 0, 3), StripePlan::new(1, 3, 6)],
    )
    .expect("valid plan");

    // When
    let result = plan.validate_tensor_shape(&[2, 4, 4]);

    // Then
    assert_eq!(
        result,
        Err(ExecutionPlanError::MatrixShapeMismatch {
            expected_rows: 6,
            expected_k: 4,
            actual_rows: 8,
            actual_k: 4,
        })
    );
}

#[test]
fn execution_plan_error_reports_context_without_source() {
    // Given
    let error = ExecutionPlanError::StripeGap {
        previous_end: 4,
        next_start: 5,
    };

    // When
    let message = error.to_string();
    let source = std::error::Error::source(&error);

    // Then
    assert_eq!(message, "stripe row gap between 4 and 5");
    assert!(source.is_none());
}
