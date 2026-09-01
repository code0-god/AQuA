# AQuA

**Adaptive Quantization Accelerator**

AQuA targets an end-to-end LLM accelerator that integrates hardware-native
adaptive quantization into transformer execution. The current milestone is a
CPU-shadow Candle integration plus deterministic Rust ExSIA and RaCo
references, profile-safe Q8_HP1 loading, and canonical integer-weight
extraction for future BSV implementation.

## Implemented architecture

```text
Candle Tensor
       |
       v
Device::Aqua / AquaStorage
       |
       +---------------- unsupported operation --> Candle CPU fallback
       |
       `---------------- supported floating matmul
                                |
                                v
      exact logical layout materialization
               |
               v
       canonical F32 HostTensor
               |
               v
 FixedStripePlanner (integration policy only)
               |
               v
       ActivationExecutionPlan
               |
               v
       ReferenceExsia (Rust)
               |
        +-----------------------------+
        |                             |
        v                             v
 dense I4/I8/I16                ResidualStripe
        |                       local row / K / i32
        |                             |
        |                             v
        |                    Rust RaCo Reference
        |                             |
        |                  +----------+----------+
        |                  |          |          |
        |                  v          v          v
        |             balanced    compact K  active lanes
        |               radix
        |                  \          |          /
        |                   \         |         /
        |                    v        v        v
        |                       integer dot
        |                            |
        |                            v
        |                    radix composition
        |                            |
        |                            v
        |                 raw integer correction
        |
        v
 dequantize_dense: q * 2^theta
        Q-only lossy reconstruction
               |
               v
        Candle CPU matmul
               |
               v
 Device::Aqua CPU-shadow result
```

The implemented crates have these responsibilities:

* `aqua-protocol`: Candle-independent tensor and protocol semantics.
* `aqua-runtime`: canonical F32 `HostTensor` plus validated activation matrix
  and stripe-plan geometry. It validates plans; it does not choose hardware
  tiles.
* `aqua-exsia`: ExSIA-specific contracts, the canonical sequential reference,
  and public dense Q-only dequantization. `dequantize_dense` deliberately
  ignores residual events and is not residual-aware reconstruction.
* `aqua-raco`: deterministic signed-21-bit balanced-radix decomposition,
  canonical 32-wide block/K and active-lane compaction, dense integer
  weight-code execution, radix composition, and raw integer correction.
  Public read-only stage contracts are suitable for BSV golden comparison.
* `aqua-weight`: Candle-independent Q8_HP1 raw-block parsing, canonical
  `[row][K]` integer codes, per-block left shifts, exact row-scale exponents,
  deterministic role classification, registry, and model statistics.
* `aqua-candle`: framework adapter, integration-only `FixedStripePlanner`,
  `DenseQOnlyAquaExecutor`, GGUF weight-capture executor, and `Device::Aqua`
  factories.
* `third_party/candle`: the AQuA Candle fork. Its feature-gated Aqua backend
  stores CPU shadows, decodes Q8_H numeric IDs only in profile-identified
  GGUF files, exposes raw GGUF tensors to an injected executor, and falls back
  to normal CPU execution.
* `aqua-host`: host-boundary smoke executable plus `inspect-hp1` model
  inspection and canonical parity command.
* `hw/bsv`: source and testbench boundary for future hardware work.

`tensor_to_host` accepts supported floating tensors on any Candle device by
copying them to CPU, converting them to F32, making their logical layout
contiguous, and preserving their logical shape. `host_to_tensor_on` constructs
a canonical host tensor on a selected Candle device; `host_to_tensor` remains
the CPU convenience API.

`DenseQOnlyAquaExecutor` intercepts dense F16, BF16, F32, and F64 matmul. It
materializes both Candle request layouts in exact logical order, canonicalizes
them to F32, runs ExSIA over the left activation using an externally
constructed execution plan, performs lossy Q-only `q * 2^theta`
reconstruction, and delegates the final multiplication to Candle's CPU
matmul. Mismatched or unsupported dtypes and non-intercepted operations use
the CPU-shadow fallback.

`FixedStripePlanner` is deterministic bridge policy for integration and tests.
It is intentionally located in `aqua-candle`; it is not a runtime tiler,
hardware-capacity model, scratchpad planner, or part of canonical ExSIA
configuration.

## ExSIA boundary

The canonical ExSIA input is a validated contiguous F32 `HostTensor` paired
with an externally supplied `ActivationExecutionPlan`. Stripe boundaries are
execution context, target precision is ExSIA configuration, and
`AQUA_BLOCK_SIZE = 32` is the shared immutable K-coordinate contract for
ExSIA, RaCo, and future integer-weight scale groups. Changing stripe grouping
can change stripe exponents and thus execution semantics.

ExSIA emits clipped quantized values, per-stripe theta values, and
stripe-scoped residual events. Residual coordinates use stripe-local row and
original logical K. The current Candle bridge consumes only clipped values and
theta. The Rust RaCo reference consumes residuals separately and computes raw
`residual integer × integer weight code` corrections without applying
activation theta or weight scales.

The Rust reference is the semantic contract for a future BSV implementation.
AQuA deliberately flushes subnormal activation values to zero to make the
hardware-oriented behavior explicit.

## Current scope and deferred work

This milestone provides model-quality/emulation plumbing, not accelerator
residency or acceleration. Specifically:

* `Device::Aqua` uses CPU-shadow `Storage::Aqua`.
* Quantized Candle weights remain in existing CPU/CUDA/Metal `QStorage`; there
  is no `QStorage::Aqua`.
* Dense Q-only reconstruction is lossy and performs no residual addition.
* RaCo balanced radix, logical stripe work, integer weight-code execution,
  radix composition, and direct exact-parity tests are implemented.
* Q8_HP1 GGUF profile detection, load interception, canonical weight
  extraction, block-left-shift statistics, and row-scale statistics are
  implemented.
* There is no full Candle RaCo executor, ExSIF scale integration, physical
  packet format, or accelerator-resident RaCo storage.
* There is no block-shift LUT contract, BSV HP1 weight provider, physical
  weight image, Q8_HP1 execution path, or RaCo/weight-scale merge.
* There is no BSV ExSIA datapath, transport, hardware tiler, asynchronous
  execution, systolic-array connection, or nonlinear-operation integration.
* Intermediate tensors are not accelerator-resident.
* There is no ExSIF, KV-cache offload, UART, PCIe, DMA, or FPGA board support.

RaCo remains separate from Q-only dequantization. The Rust core stops at raw
integer correction; floating scale integration and Candle result addition are
future layers.

## Candle fork

Candle is a Git submodule at `third_party/candle`, tracking the AQuA integration
fork and branch declared in `.gitmodules`:

```text
https://github.com/code0-god/candle-AQuA.git
aqua/integration
```

The Candle-side executor trait contains no AQuA repository types, preserving
the dependency direction: Candle defines an injection boundary and
`aqua-candle` implements it. The unrelated `aqua-runtime::AquaExecutor` host
trait is not modified or conflated with `candle_core::AquaExecutor`.

After a fresh clone:

```bash
git submodule update --init --recursive
```

## Development

```bash
cargo fmt --check
cargo check --workspace
cargo test --workspace
cargo test -p aqua-candle --test round_trip
cargo test -p aqua-candle --test aqua_device
cargo clippy --workspace --all-targets -- -D warnings
cargo run -p aqua-host
cargo run -p aqua-host --release -- inspect-hp1 <model.gguf>
```

## Roadmap

1. Define the model-compiled block-shift LUT contract from measured profiles.
2. Implement the BSV Q8_HP1 weight provider without changing canonical weight
   meaning.
3. Integrate RaCo correction scaling with future ExSIF weight scales.
4. Implement and bit-exactly validate the BSV ExSIA and RaCo datapaths.
5. Add explicit hardware tiling, transport, and asynchronous execution.
6. Add nonlinear transformer operations and accelerator-resident tensors.
