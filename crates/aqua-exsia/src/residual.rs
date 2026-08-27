/// Sparse residual for an outlier selected by ExSIA.
///
/// `block_index` identifies the ExSIA block containing the outlier.
/// `element_index` identifies the element within that block.
/// `residual` stores the signed integer residual associated with that element.

#[derive(Clone, Copy, Debug, Eq, PartialEq)] // 복사 가능, {:?} 출력 가능, == / != 비교 가능.
pub struct ResidualEntry {
    block_index: usize,   // outlier가 속한 block 번호.
    element_index: usize, // block 내부의 element 번호.
    residual: i32,        // signed integer residual 값.
}

impl ResidualEntry {
    pub const fn new(block_index: usize, element_index: usize, residual: i32) -> Self {
        // Self = ResidualEntry.
        Self {
            block_index, // `block_index: block_index`의 축약형.
            element_index,
            residual,
        }
    }

    pub const fn block_index(&self) -> usize {
        self.block_index // usize는 Copy이므로 값을 복사해서 반환.
    }

    pub const fn element_index(&self) -> usize {
        self.element_index
    }

    pub const fn residual(&self) -> i32 {
        self.residual // i32 역시 Copy.
    }
}

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct Residuals {
    entries: Vec<ResidualEntry>, // 여러 residual entry를 동적 배열에 저장.
}

impl Residuals {
    pub const fn new() -> Self {
        Self {
            entries: Vec::new(), // 빈 Vec 생성. len=0, capacity=0.
        }
    }

    pub fn with_capacity(capacity: usize) -> Self {
        Self {
            entries: Vec::with_capacity(capacity), // 미리 capacity만큼 메모리 공간 확보.
        }
    }

    pub fn push(&mut self, entry: ResidualEntry) {
        self.entries.push(entry); // Vec 끝에 entry 추가.
    }

    pub fn len(&self) -> usize {
        self.entries.len() // 현재 저장된 entry 개수.
    }

    pub fn is_empty(&self) -> bool {
        self.entries.is_empty() // entry가 0개면 true.
    }

    pub fn entries(&self) -> &[ResidualEntry] {
        &self.entries // Vec을 소유권 이동 없이 slice로 빌려줌.
    }

    pub fn iter(&self) -> impl Iterator<Item = &ResidualEntry> {
        self.entries.iter() // entry를 하나씩 &ResidualEntry로 순회.
    }

    pub fn clear(&mut self) {
        self.entries.clear(); // 모든 element 제거. Residuals는 계속 사용 가능.
    }

    pub fn into_entries(self) -> Vec<ResidualEntry> {
        self.entries // self의 ownership을 받아 내부 Vec 자체를 반환.
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
