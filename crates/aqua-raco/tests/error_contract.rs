use aqua_raco::RacoError;

#[test]
fn residual_range_error_reports_typed_context() {
    // Given
    let error = RacoError::ResidualOutOfRange {
        value: 1_048_576,
        minimum: -1_048_576,
        maximum: 1_048_575,
    };

    // When
    let message = error.to_string();

    // Then
    assert_eq!(
        message,
        "residual 1048576 is outside signed RaCo range -1048576..=1048575"
    );
}
