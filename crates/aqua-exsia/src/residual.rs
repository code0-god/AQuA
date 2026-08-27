/// Sparse residual for an outlier selected by ExSIA.
///
/// 'block_index' identifies the ExSIA block containing the outlier.
/// 'element_index' identifies the element within that block.
/// 'residual' stores the signed integer residual associated with that element.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct ResidualEntry {
    block_index: usize,
    element_index: usize,
    residual: i32,
}

impl ResidualEntry {
    pub const fn new(block_index: usize, element_index: usize, residual: i32) -> Self {
        Self {
            block_index,
            element_index,
            residual,
        }
    }

    pub const fn block_index(&self) -> usize {
        self.block_index
    }

    pub const fn element_index(&self) -> usize {
        self.element_index
    }

    pub const fn residual(&self) -> i32 {
        self.residual
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Residuals {
    entries: Vec<ResidualEntry>,
}

impl Residuals {
    pub const fn new() -> Self {
        Self {
            entries: Vec::new(),
        }
    }

    pub fn with_capacity(capacity: usize) -> Self {
        Self {
            entries: Vec::with_capacity(capacity),
        }
    }

    pub fn push(&mut self, entry: ResidualEntry) {
        self.entries.push(entry);
    }

    pub fn len(&self) -> usize {
        self.entries.len()
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty()
    }

    pub fn entries(&self) -> &[ResidualEntry] {
        &self.entries
    }

    pub fn iter(&self) -> impl Iterator<Item = &ResidualEntry> {
        self.entries.iter()
    }

    pub fn clear(&mut self) {
        self.entries.clear();
    }

    pub fn into_entries(self) -> Vec<ResidualEntry> {
        self.entries
    }
}

#[cfg(test)]
mod tests {
    use super::{ResidualEntry, Residuals};

    #[test]
    fn entry_tracks_location_and_residual() {
        let entry = ResidualEntry::new(3, 17, -42);

        assert_eq!(entry.block_index(), 3);
        assert_eq!(entry.element_index(), 17);
        assert_eq!(entry.residual(), -42);
    }

    #[test]
    fn residuals_preserve_insertion_order() {
        let mut residuals = Residuals::new();

        residuals.push(ResidualEntry::new(0, 4, 11));
        residuals.push(ResidualEntry::new(0, 21, -7));
        residuals.push(ResidualEntry::new(2, 3, 29));

        assert_eq!(residuals.len(), 3);

        assert_eq!(
            residuals.entries(),
            &[
                ResidualEntry::new(0, 4, 11),
                ResidualEntry::new(0, 21, -7),
                ResidualEntry::new(2, 3, 29),
            ]
        );
    }

    #[test]
    fn empty_residuals_are_empty() {
        let residuals = Residuals::new();

        assert!(residuals.is_empty());
        assert_eq!(residuals.len(), 0);
    }

    #[test]
    fn clear_removes_all_entries() {
        let mut residuals = Residuals::new();

        residuals.push(ResidualEntry::new(1, 7, 15));
        residuals.clear();

        assert!(residuals.is_empty());
    }
}
