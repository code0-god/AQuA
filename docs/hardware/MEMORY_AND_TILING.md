# AQuA Memory and Tiling Architecture

## Logical matrices

```text
Activation:          A[M, K]
GGUF weight source:  W_source[J, K]
Matrix-engine view:  W[K, J]
Output:              C[M, J]
```

Rust uses `n` for output columns. BSV descriptors use the same logical
dimension even where diagrams call it J.

## Five distinct units

### Physical array dimension

`array_dim` is the physical row and column count. One ordinary array
execution handles at most `array_dim` K elements and `array_dim` output
columns.

### Macro tile

Host-selected factors count `array_dim`-wide matrices:

```text
macro_m_rows     = tile_i_factor * array_dim
macro_n_columns  = tile_j_factor * array_dim
macro_k_elements = tile_k_factor * array_dim
```

Logical matrix edges may produce partial extents.

### ExSIA stripe

```text
stripe_rows = min(macro_m_rows, remaining logical M)
```

An ExSIA stripe is execution context, not ExSIA configuration. The current
canonical Rust ExSIA reference processes every logical K element in a stripe.
ExSIA capacity therefore uses full logical K, not macro K.

### Array work

One array work item is bounded by physical dimensions:

```text
work_i_rows    <= array_dim
work_j_columns <= array_dim
```

A macro M/J tile contains one or more array works.

### K fragment and HP1 block

An HP1 block owns 32 K elements. A physical K fragment must not cross that
boundary:

```text
remaining_logical_k = work_k_end - k_start
remaining_in_block  = 32 - (k_start % 32)

k_fragment_count =
    min(array_dim, remaining_logical_k, remaining_in_block)
```

`macro_k_elements` may exceed 32. `WorkScheduler` decomposes it into
block-bounded fragments.

## Hierarchy

```text
macro M tile
└── ExSIA stripe

macro N/J tile
└── one or more array_dim-wide array works

macro K tile
└── one or more HP1 blocks
    └── one or more array-dimension-bounded K fragments
```

## Resource-aware host plan

`AquaHardwareGeometry` describes:

- physical array dimension;
- activation and weight scratchpad banks and rows;
- dedicated HP1 metadata capacity in bytes;
- accumulator banks and rows;
- ExSIA slot count and bytes;
- activation, weight, and accumulator element widths;
- HP1 block-shift and row-scale widths;
- independent double-buffer enablement.

`AquaTileSelector` keeps Gemmini's J, then I, then K greedy growth order but
tests every candidate against all AQuA resources.

The explicit HP1 metadata capacity is required because `Hp1MetaMem` is
physically separate from `WeightSpad`; metadata cannot consume an unspecified
remainder of weight-code storage.

`AquaTilePlan` retains selected factors, concrete logical extents, padded K,
and resource usage. Its stripe rows generate an existing validated
`ActivationExecutionPlan`. `FixedStripePlanner` remains separate
integration/test policy.

The selected stripe plan is frozen before canonical ExSIA execution. Hardware
geometry therefore chooses an explicit numerical execution context; it does
not mutate ExSIA grouping internally. Re-running a shape with different
geometry may select a different valid plan and therefore different canonical
stripe results. Re-running the same geometry and shape must select the same
plan.

## Memory lifetime

| Memory | Meaning | Lifetime |
|---|---|---|
| `ExsiaStripeMem` | Wide values, exponents, outlier masks | Until stripe folding commits |
| `ActivationSpad` | Clipped activation Q values | Across all J tiles for the stripe |
| `WeightSpad` | Current or next HP1 code tile/fragment | Matching J/K work |
| `Hp1MetaMem` | Block left shifts and row-scale metadata | Matching J/K tile |
| `AccumulatorMem` | Future dense and RaCo contributions | Until output tile completes |

Residual packet memory is not included in the first ExSIA slot budget.

## Local memory regions

`AquaLoopMatmul` is the sole future allocator of local-memory slots and base
ranges. Schedulers carry those allocations but do not create them. Load and
store controllers derive offsets inside assigned ranges.

Controllers exchange typed addresses:

```text
AquaLocalAddr {
    region,
    slot,
    bank,
    row
}
```

Activation, weight, HP1 metadata, accumulator, ExSIA stripe, and future RaCo
regions remain logically distinct. Banked activation and weight memories use:

```text
bank     = global_row % bank_count
bank_row = global_row / bank_count
```

Within an allocated slot, canonical row numbering is:

```text
activation_global_row =
    activation_base
    + local_m * macro_k_groups
    + local_k_group

weight_global_row =
    weight_base
    + local_j * macro_k_groups
    + local_k_group
```

`macro_k_groups = ceil(macro_k_count / array_dim)`. HP1 metadata and
accumulator allocations use separate bases and cannot alias activation or
weight ranges. Slot partition bounds are validated when a macro tile is
installed. Provider requests carry an already allocated local destination;
the provider never chooses or rewrites it.

Double-buffer slot remains explicit in addresses even before overlap
execution is implemented.

## Scratchpad behavior

The canonical interface specifies:

- accepted read request followed by defined-latency response;
- one buffered response held until consumption;
- backpressure;
- single-port write priority over read acceptance;
- lane-masked writes preserving unselected lanes;
- simulation bounds checks.

The first physical backend may use BSC-supported register or BRAM storage.
The interface remains replaceable.

## Accumulator behavior

Accumulator banks map output-column lanes. Rows map local output rows.

```text
accumulate = False: new_value = contribution
accumulate = True:  new_value = old_value + contribution
```

Arithmetic uses parameterized accumulator types. There is no silent
narrowing, saturation, dense/RaCo arbitration, or row-right-shift unit in
this foundation.

## Provider boundary

```text
LoadController
    requests canonical activation, weight, and HP1 metadata
        ↓
AquaMemoryPort
    simulator provider now
    physical DMA adapter later
        ↓
banked local memories
```

Provider requests identify job, stripe, macro tile, array work, K fragment,
memory kind, tensor ID, logical range, and local destination. Responses may
be same-cycle or delayed; tags determine destinations.

Weight source order remains `[J lane][K fragment]`. A future PE preload
adapter performs tile-local `[K fragment][J lane]` reorder. The full model is
never transposed.

`StoreController` reads raw accumulator rows and emits tagged output writes.
Completion requires output acknowledgement. Row-right-shift arithmetic
remains a later stage.

## Deferred overlap

Gemmini's two loop contexts motivate a future `AquaLoopMatmul`:

```text
current context: execute and store
next context:    load and prepare
```

This foundation preserves slots and controller boundaries but does not
implement concurrent double-buffer execution.

Traversal layers remain separate:

```text
AquaLoopMatmul: macro M/N/K tile traversal and slot allocation
MatmulScheduler: array work J-before-I inside one macro M/N tile
WorkScheduler: block-bounded fragments inside one macro K range
```
