#!/usr/bin/env bash
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cargo test \
    --manifest-path "$root/Cargo.toml" \
    -p aqua-protocol \
    uses_canonical_k_block_size

make \
    -C "$root/hw/bsv" \
    bsv-test-one \
    TOP=mkTbHardwareContracts
