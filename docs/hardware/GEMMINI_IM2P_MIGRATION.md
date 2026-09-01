# Gemmini and IM2P Migration Contract

This document defines which architecture contracts AQuA adapts from Gemmini
and IM2P.sim. It does not import either repository into the AQuA source tree.

## Source priority

Conflicts are resolved in this order:

1. AQuA Rust canonical semantics:
   `AQUA_BLOCK_SIZE`, `ActivationExecutionPlan`, ExSIA stripes,
   `ResidualStripe`, RaCo, and `Hp1MatrixWeight`.
2. IM2P.sim BSV execution behavior: scheduler handshakes, K fragments,
   lookahead, provider tags, and ordered completion.
3. Gemmini memory and loop architecture: local addresses, banked memories,
   accumulator behavior, double buffering, and controller separation.
4. llama.cpp-gemmini host tile-factor policy.

A lower-priority reference may change AQuA hardware structure. It may not
silently change higher-priority numerical meaning. Tile selection produces an
explicit `ActivationExecutionPlan` before ExSIA starts; that plan is part of
the canonical Rust input. Different validated plans may produce different
stripe exponents and residuals, but each result remains deterministic for its
declared plan. RTL may not retile or regroup a stripe after that boundary.

## IM2P.sim to AQuA

| IM2P.sim | AQuA | Migrated behavior |
|---|---|---|
| `src/control/WorkTypes.bsv` | `AquaWorkTypes.bsv` | Descriptor and work field meaning, rewritten with tensor IDs and typed local addresses |
| `src/control/MatmulScheduler.bsv` | `MatmulScheduler.bsv` | Stripe ordering, J-before-I traversal, two-entry FIFOs, immediate lookahead, ordered completion |
| `src/control/WorkScheduler.bsv` | `WorkScheduler.bsv` | K progression, block-bounded fragments, block index, accumulation, one-fragment lookahead |
| `src/io/HostMemoryTypes.bsv` | `AquaMemoryTypes.bsv` | Tagged request and response shape without embedded host pointers |
| `src/common/Arithmetic.bsv` | Later `Arithmetic.bsv` | Deferred until WS datapath migration |
| `src/array/PE.bsv` | Later `PE.bsv` | Deferred until WS datapath migration |
| `src/array/InputSkew.bsv` | Later `InputSkew.bsv` | Deferred until WS datapath migration |
| `src/array/SystolicArray.bsv` | Later `SystolicArray.bsv` | Deferred until WS datapath migration |
| `src/array/SystolicEngine.bsv` | Later `SystolicEngine.bsv` | Deferred until WS datapath migration |
| `src/accumulator/Accumulator.bsv` | Test model only | Production state uses banked `AccumulatorMem` |
| `src/vector/VectorUnit.bsv` | Later HP1-specific units | Generic vector scaling policy is not migrated |
| `src/core/IM2PCore.bsv` | Decomposed controllers | Monolithic core is not copied |

The pinned scheduler behavior is adapted, not mechanically translated:

- `MatmulScheduler` has two-entry publication and completion FIFOs.
- J array work advances before I array work inside the current macro M/N
  tile.
- Async stripes must be contiguous, non-overlapping, and in bounds.
- One next stripe may be prepared while current work executes.
- Stripe completion is emitted only after its final work completes.
- `WorkScheduler` uses:

  ```text
  fragment_count =
      min(array_dim, remaining_k, remaining_in_hp1_block)
  ```

- HP1 block boundaries do not reset full-matmul accumulation.
- Host addresses and pointer arithmetic are removed from schedulers.

## Gemmini to AQuA

| Gemmini | AQuA | Migrated behavior |
|---|---|---|
| `GemminiConfigs.scala` / `Configs.scala` | `AquaHardwareGeometry` | Array dimension, bank geometry, row widths, resource invariants |
| `LocalAddr.scala` | `AquaLocalAddr.bsv` | Typed local region, slot, bank, and row |
| `ScratchpadBank` in `Scratchpad.scala` | `ScratchpadBank.bsv` | Buffered reads, backpressure, write priority, masks |
| Scratchpad composition | Separate activation, weight, and HP1 metadata memories | Concurrent ownership without one packed address space |
| `AccumulatorMem.scala` | `AccumulatorMem.bsv` | Wide banked state, read-modify-write accumulation, explicit arbitration |
| `LoopMatmul.scala` | Later `AquaLoopMatmul` | Current/next contexts, memory partitioning, completion-driven promotion |
| `LoadController.scala` | `LoadController.bsv` | Row/range request issue and local destination tracking |
| `StoreController.scala` | `StoreController.bsv` | Accumulator reads, output requests, acknowledgement-gated completion |
| `Controller.scala` | Separate AQuA controllers | Load, execute, and store ownership remains separated |
| Reservation station / ROB | Deferred | Not part of this migration foundation |
| DMA / TileLink / TLB | Future adapter below `AquaMemoryPort` | Not part of the core contract |

Gemmini's packed 32-bit local address is not copied. AQuA uses an explicit
region plus slot, bank, and row fields.

## llama.cpp-gemmini host selection

The pinned llama.cpp-gemmini tree calls `gemmini_set_tile_ws`, but the
implementation is supplied by external `gemmini.h` through
`GEMMINI_SW_PATH`. AQuA rewrites the observed behavior in checked Rust:

1. Pad M, N, and K independently to `array_dim`.
2. Calculate double-buffered scratchpad and accumulator capacities.
3. Select initial I, J, and K factors from padded dimensions and resource
   bounds.
4. Repeatedly attempt J, then I, then K growth.
5. Stop when no factor can grow.

The row contracts are:

```text
scratchpad_rows = (tile_i * tile_k + tile_k * tile_j) * array_dim
accumulator_rows = tile_i * tile_j * array_dim
```

AQuA adds activation, weight, HP1 metadata, accumulator, and full-logical-K
ExSIA slot constraints. LayerNorm and Softmax special cases are excluded.

## Ownership gate

| Question | Owner |
|---|---|
| Who chooses tile factors? | Rust host/runtime `AquaTileSelector` |
| Who traverses macro tiles? | Future RTL `AquaLoopMatmul` |
| Who chooses K fragments? | RTL `WorkScheduler` |
| Who determines ExSIA stripe rows? | `AquaTilePlan`, derived from tile-I factor and frozen into `ActivationExecutionPlan` before ExSIA |
| Who allocates local regions and slots? | Future RTL `AquaLoopMatmul` |
| Who derives addresses inside an allocation? | Load and store controllers |
| Who services external requests? | Provider adapter implementing `AquaMemoryPort` |
| Where does physical DMA attach? | Below `AquaMemoryPort`, in a later phase |

Traversal authority is non-overlapping:

- `AquaLoopMatmul` selects the current macro M/N/K tile and its local-memory
  slot allocation.
- `MatmulScheduler` expands only that macro M/N tile into DIM-bounded array
  works, with J innermost and I outermost.
- `WorkScheduler` fragments only that macro K range without crossing HP1
  blocks.

## Explicit non-goals

This is not a Gemmini clone.

This is not a line-by-line Chisel-to-BSV translation.

The migration excludes RoCC, RocketChip parameters, TileLink, TLB/PTW,
virtual memory, physical DMA, reservation stations, ROBs, Gemmini ISA,
TilerFSM translation, convolution, im2col, pooling, output-stationary
datapaths, training support, and generic activation hardware.
