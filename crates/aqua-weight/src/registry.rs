use crate::{Hp1MatrixWeight, WeightError};
use std::collections::{btree_map::Entry, BTreeMap};

#[derive(Clone, Debug, Default, Eq, PartialEq)]
pub struct AquaWeightRegistry {
    weights: BTreeMap<String, Hp1MatrixWeight>,
}

impl AquaWeightRegistry {
    pub const fn new() -> Self {
        Self {
            weights: BTreeMap::new(),
        }
    }

    pub fn insert(&mut self, weight: Hp1MatrixWeight) -> Result<(), WeightError> {
        let name = weight.descriptor().name().to_owned();
        match self.weights.entry(name) {
            Entry::Vacant(entry) => {
                entry.insert(weight);
                Ok(())
            }
            Entry::Occupied(entry) => Err(WeightError::DuplicateTensorName {
                name: entry.key().to_owned(),
            }),
        }
    }

    pub fn get(&self, name: &str) -> Option<&Hp1MatrixWeight> {
        self.weights.get(name)
    }

    pub fn iter(&self) -> impl Iterator<Item = (&str, &Hp1MatrixWeight)> {
        self.weights
            .iter()
            .map(|(name, weight)| (name.as_str(), weight))
    }

    pub fn len(&self) -> usize {
        self.weights.len()
    }

    pub fn is_empty(&self) -> bool {
        self.weights.is_empty()
    }
}
