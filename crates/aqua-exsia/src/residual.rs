use aqua_protocol::AQUA_BLOCK_SIZE;

/// Sparse residual generated during ExSIA stripe folding.
///
/// `local_row` is relative to the stripe's `row_start`.
/// `k` is the original logical activation coordinate in the reduction
/// dimension.
/// `residual` is the signed integer value separated by target-precision
/// clipping at the final stripe scale.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ResidualEvent {
    local_row: usize,
    k: usize,
    residual: i32,
}

impl ResidualEvent {
    pub(crate) const fn new(local_row: usize, k: usize, residual: i32) -> Self {
        Self {
            local_row,
            k,
            residual,
        }
    }

    pub const fn local_row(&self) -> usize {
        self.local_row
    }

    pub const fn k(&self) -> usize {
        self.k
    }

    pub const fn residual(&self) -> i32 {
        self.residual
    }

    pub const fn global_row(&self, stripe_row_start: usize) -> usize {
        stripe_row_start + self.local_row
    }

    pub const fn block_index_in_row(&self) -> usize {
        self.k / AQUA_BLOCK_SIZE
    }

    pub const fn element_index_in_block(&self) -> usize {
        self.k % AQUA_BLOCK_SIZE
    }
}

/// Stripe-scoped residual events emitted by ExSIA.
///
/// This is the canonical software input contract for the future RaCo path.
#[derive(Clone, Debug, Eq, PartialEq)]
pub struct ResidualStripe {
    stripe_index: usize,
    row_start: usize,
    row_count: usize,
    logical_k: usize,
    events: Vec<ResidualEvent>,
}

impl ResidualStripe {
    pub(crate) fn with_capacity(
        stripe_index: usize,
        row_start: usize,
        row_count: usize,
        logical_k: usize,
        capacity: usize,
    ) -> Self {
        Self {
            stripe_index,
            row_start,
            row_count,
            logical_k,
            events: Vec::with_capacity(capacity),
        }
    }

    pub const fn stripe_index(&self) -> usize {
        self.stripe_index
    }

    pub const fn row_start(&self) -> usize {
        self.row_start
    }

    pub const fn row_count(&self) -> usize {
        self.row_count
    }

    pub const fn row_end(&self) -> usize {
        self.row_start + self.row_count
    }

    pub const fn logical_k(&self) -> usize {
        self.logical_k
    }

    pub fn events(&self) -> &[ResidualEvent] {
        &self.events
    }

    pub fn len(&self) -> usize {
        self.events.len()
    }

    pub fn is_empty(&self) -> bool {
        self.events.is_empty()
    }

    pub fn iter(&self) -> impl Iterator<Item = &ResidualEvent> {
        self.events.iter()
    }

    pub fn into_events(self) -> Vec<ResidualEvent> {
        self.events
    }

    pub(crate) fn push(&mut self, event: ResidualEvent) {
        debug_assert!(event.local_row() < self.row_count);
        debug_assert!(event.k() < self.logical_k);
        debug_assert_ne!(event.residual(), 0);
        self.events.push(event);
    }
}

#[cfg(test)]
mod tests {
    use super::{ResidualEvent, ResidualStripe};

    #[test]
    fn event_tracks_local_row_k_and_residual() {
        // Given
        let event = ResidualEvent::new(3, 67, -42);

        // When
        let coordinates = (event.local_row(), event.k(), event.residual());

        // Then
        assert_eq!(coordinates, (3, 67, -42));
    }

    #[test]
    fn event_derives_block_and_element_indices() {
        // Given
        let event = ResidualEvent::new(0, 67, 11);

        // When
        let block = event.block_index_in_row();
        let element = event.element_index_in_block();

        // Then
        assert_eq!(block, 2);
        assert_eq!(element, 3);
    }

    #[test]
    fn event_computes_global_row() {
        // Given
        let event = ResidualEvent::new(3, 0, 11);

        // When
        let global_row = event.global_row(8);

        // Then
        assert_eq!(global_row, 11);
    }

    #[test]
    fn stripe_tracks_metadata() {
        // Given
        let stripe = ResidualStripe::with_capacity(3, 8, 2, 65, 0);

        // When
        let metadata = (
            stripe.stripe_index(),
            stripe.row_start(),
            stripe.row_count(),
            stripe.logical_k(),
        );

        // Then
        assert_eq!(metadata, (3, 8, 2, 65));
    }

    #[test]
    fn stripe_preserves_insertion_order() {
        // Given
        let mut stripe = ResidualStripe::with_capacity(0, 0, 2, 33, 4);
        let expected = [
            ResidualEvent::new(0, 1, 11),
            ResidualEvent::new(0, 32, -7),
            ResidualEvent::new(1, 2, 29),
        ];

        // When
        for event in expected {
            stripe.push(event);
        }

        // Then
        assert_eq!(stripe.events(), &expected);
        assert_eq!(stripe.iter().copied().collect::<Vec<_>>(), expected);
    }

    #[test]
    fn empty_stripe_is_empty() {
        // Given
        let stripe = ResidualStripe::with_capacity(0, 0, 1, 32, 0);

        // When
        let metadata = (stripe.is_empty(), stripe.len());

        // Then
        assert_eq!(metadata, (true, 0));
    }

    #[test]
    fn stripe_row_end_is_derived_correctly() {
        // Given
        let stripe = ResidualStripe::with_capacity(3, 8, 2, 65, 0);

        // When
        let row_end = stripe.row_end();

        // Then
        assert_eq!(row_end, 10);
    }

    #[test]
    fn into_events_transfers_ownership() {
        // Given
        let mut stripe = ResidualStripe::with_capacity(0, 0, 1, 32, 1);
        let event = ResidualEvent::new(0, 7, 15);
        stripe.push(event);

        // When
        let events = stripe.into_events();

        // Then
        assert_eq!(events, vec![event]);
    }
}
