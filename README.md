# AQuA

**Adaptive Quantization Accelerator**

AQuA targets an end-to-end LLM accelerator that integrates hardware-native
adaptive quantization into transformer execution. The current milestone is a
CPU-shadow Candle integration that exercises the canonical Rust ExSIA
reference through a real `Device::Aqua` matmul dispatch.

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
        +------+------+
        |             |
        v             v
 dense I4/I8/I16   ResidualStripe events
        |             |
        |             `-- retained, not applied in this milestone
        |                         |
        |                         `-- RACO (planned)
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
* `aqua-candle`: framework adapter, integration-only `FixedStripePlanner`,
  `DenseQOnlyAquaExecutor`, and the `Device::Aqua` factory.
* `third_party/candle`: the AQuA Candle fork. Its feature-gated Aqua backend
  stores CPU shadows, injects an operation executor, and falls back to normal
  CPU execution for operations the executor does not handle.
* `aqua-host`: host-boundary smoke executable.
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
execution context, while block size and target precision are ExSIA algorithm
configuration. Changing stripe grouping can change stripe exponents and thus
execution semantics.

ExSIA emits clipped quantized values, per-stripe theta values, and
stripe-scoped residual events. Residual coordinates use stripe-local row and
original logical K. The current Candle bridge consumes only clipped values and
theta. Residual events remain available for future residual compensation but
are not added to the dense activation or matmul result.

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
* There is no RACO crate, packetization, executor, or correction path.
* There is no BSV ExSIA datapath, transport, hardware tiler, asynchronous
  execution, systolic-array connection, or nonlinear-operation integration.
* Intermediate tensors are not accelerator-resident.
* There is no ExSIF, KV-cache offload, UART, PCIe, DMA, or FPGA board support.

RACO is the reserved name for future residual compensation. Its absence here
is deliberate; Q-only dequantization must not be described as canonical
residual-aware reconstruction.

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
```

## Roadmap

1. Add residual-aware reconstruction and RACO semantics separately from the
   existing dense Q-only path.
2. Generate golden vectors from real Candle LLM activations.
3. Implement and bit-exactly validate the BSV ExSIA datapath.
4. Connect ExSIA and future residual compensation to accelerator execution.
5. Add explicit hardware tiling, transport, and asynchronous execution.
6. Add nonlinear transformer operations and accelerator-resident tensors.
