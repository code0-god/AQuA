use super::{
    execute, execute_with_plan, execution_plan, host_tensor, repeated_rows, ExsiaPrecision,
    QuantizedValues,
};

#[test]
fn executes_partial_k33_without_padding() {
    let output = execute(
        &[33],
        [vec![2.0; 32], vec![8.0]].concat(),
        ExsiaPrecision::I8,
        &[(0, 1)],
    );

    assert_eq!(
        output.quantized,
        QuantizedValues::I8([vec![64_i8; 32], vec![127]].concat())
    );
    assert_eq!(output.len(), 33);
    let events = output.residual_stripes[0].events();
    assert_eq!(events.len(), 1);
    assert_eq!(
        (events[0].local_row(), events[0].k(), events[0].residual()),
        (0, 32, 129)
    );
}

#[test]
fn preserves_multi_row_single_stripe_order() {
    let output = execute(
        &[2, 33],
        repeated_rows(&[1.0, -1.0], 33),
        ExsiaPrecision::I8,
        &[(0, 2)],
    );
    let expected = [vec![64_i8; 33], vec![-64_i8; 33]].concat();

    assert_eq!(output.quantized, QuantizedValues::I8(expected));
    assert_eq!(output.len(), 66);
    assert_eq!(output.residual_stripes[0].row_count(), 2);
    assert_eq!(output.residual_stripes[0].logical_k(), 33);
}

#[test]
fn preserves_multi_stripe_output_and_metadata_order() {
    let output = execute(
        &[4, 32],
        repeated_rows(&[1.0, -1.0, 2.0, -2.0], 32),
        ExsiaPrecision::I8,
        &[(0, 2), (2, 4)],
    );
    let expected = [
        vec![64_i8; 32],
        vec![-64_i8; 32],
        vec![64_i8; 32],
        vec![-64_i8; 32],
    ]
    .concat();

    assert_eq!(output.quantized, QuantizedValues::I8(expected));
    assert_eq!(output.stripe_theta, vec![-6, -5]);
    assert_eq!(output.residual_stripes.len(), 2);

    let first = &output.residual_stripes[0];
    assert_eq!(
        (first.stripe_index(), first.row_start(), first.row_count()),
        (0, 0, 2)
    );

    let second = &output.residual_stripes[1];
    assert_eq!(
        (
            second.stripe_index(),
            second.row_start(),
            second.row_count()
        ),
        (1, 2, 2)
    );
}

#[test]
fn flattens_higher_rank_rows_and_preserves_shape() {
    let output = execute(
        &[2, 2, 32],
        vec![1.0; 128],
        ExsiaPrecision::I8,
        &[(0, 2), (2, 4)],
    );

    assert_eq!(output.quantized, QuantizedValues::I8(vec![64; 128]));
    assert_eq!(output.shape, vec![2, 2, 32]);
    assert_eq!(output.len(), 128);
    assert_eq!(output.residual_stripes.len(), 2);
}

#[test]
fn executes_partial_k65_without_padding() {
    let output = execute(
        &[65],
        [vec![2.0; 64], vec![8.0]].concat(),
        ExsiaPrecision::I8,
        &[(0, 1)],
    );

    assert_eq!(
        output.quantized,
        QuantizedValues::I8([vec![64_i8; 64], vec![127]].concat())
    );
    assert_eq!(output.len(), 65);
    let events = output.residual_stripes[0].events();
    assert_eq!(events.len(), 1);
    assert_eq!(
        (events[0].local_row(), events[0].k(), events[0].residual()),
        (0, 64, 129)
    );
}

#[test]
fn executes_each_valid_stripe_plan_as_its_own_contract() {
    let shape = [4, 64];
    let values = repeated_rows(&[8.0, 2.0, 4.0, 1.0], 64);
    let tensor = host_tensor(&shape, values);
    let single_stripe = execution_plan(&shape, &[(0, 4)]);
    let split_stripes = execution_plan(&shape, &[(0, 2), (2, 4)]);

    let single_output = execute_with_plan(&tensor, ExsiaPrecision::I8, &single_stripe);
    let split_output = execute_with_plan(&tensor, ExsiaPrecision::I8, &split_stripes);

    assert_eq!(single_output.len(), 256);
    assert_eq!(single_output.residual_stripes.len(), 1);
    assert_eq!(split_output.len(), 256);
    assert_eq!(split_output.residual_stripes.len(), 2);

    for (residual, stripe) in split_output
        .residual_stripes
        .iter()
        .zip(split_stripes.stripes())
    {
        assert_eq!(residual.stripe_index(), stripe.stripe_index());
        assert_eq!(residual.row_start(), stripe.row_start());
        assert_eq!(residual.row_count(), stripe.row_count());
        assert_eq!(residual.logical_k(), 64);
    }
}
