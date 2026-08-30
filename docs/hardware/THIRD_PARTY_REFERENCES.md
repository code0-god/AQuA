# Third-Party Hardware References

No reference repository is vendored or added as an AQuA submodule. No
third-party source line is copied into AQuA. Architecture behavior is
rewritten for AQuA contracts.

## IM2P.sim

```text
Repository: https://github.com/ajou-aisa/IM2P.sim
Branch:     main
Pin:        cb0bec878694c606ac33d0cc234ae3984e60d661
License:    no LICENSE/COPYING/NOTICE file at the pinned commit
Checkout:   /tmp/aqua-reference/IM2P.sim
```

Inspected:

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/CODE_ANALYSIS_GUIDE.md`
- `docs/VERIFICATION.md`
- `src/common/{Config,Types,Arithmetic}.bsv`
- `src/array/{PE,InputSkew,SystolicArray,SystolicEngine}.bsv`
- `src/control/{ExecuteCmd,ExecuteController,WorkTypes,MatmulScheduler,WorkScheduler}.bsv`
- `src/io/HostMemoryTypes.bsv`
- `src/vector/{Scale,VectorUnit}.bsv`
- `src/accumulator/Accumulator.bsv`
- `src/core/IM2PCore.bsv`
- `sim/`
- `frontend/README.md`
- `Makefile`

Requested `docs/RTL_CYCLE_ACCOUNTING.md` does not exist at `cb0bec8`. It is
not treated as pinned source. Cycle accounting used by this migration is
limited to scheduler/testbench clock progress and excludes host wall-clock
latency.

Adapted:

- descriptor and work field meanings;
- stripe publication and completion ordering;
- J-before-I traversal;
- two-entry stripe/completion FIFOs;
- current plus one lookahead;
- K fragmentation and HP1 block boundaries;
- tagged provider request shape.

Excluded:

- monolithic `IM2PCore`;
- host-address arithmetic inside schedulers;
- register-only final memory organization;
- generic vector scaling policy;
- zero-time host provider as physical memory.

Because the pinned tree declares no repository license, AQuA does not copy
its source text. Reimplementation is behavioral and independently structured.

## Gemmini

```text
Repository: https://github.com/ucb-bar/gemmini
Branch:     master
Pin:        8c3f9923a44a2fe2c7930587be297d6d4f8c09ca
License:    BSD 3-Clause
Checkout:   /tmp/aqua-reference/gemmini
```

Inspected:

- `README.md`
- `src/main/scala/gemmini/GemminiConfigs.scala`
- `src/main/scala/gemmini/Configs.scala`
- `src/main/scala/gemmini/LocalAddr.scala`
- `src/main/scala/gemmini/Scratchpad.scala`
- `src/main/scala/gemmini/AccumulatorMem.scala`
- `src/main/scala/gemmini/LoopMatmul.scala`
- `src/main/scala/gemmini/Controller.scala`
- `src/main/scala/gemmini/LoadController.scala`
- `src/main/scala/gemmini/StoreController.scala`
- `src/main/scala/gemmini/ExecuteController.scala`
- `src/main/scala/gemmini/ReservationStation.scala`
- `src/main/scala/gemmini/TilerController.scala`

Adapted:

- parameter-derived memory geometry;
- typed local region/bank/row meaning;
- buffered scratchpad reads and masked writes;
- accumulator read-modify-write behavior;
- current/next loop context concept;
- separated load/execute/store ownership.

Excluded:

- RoCC and Gemmini ISA;
- RocketChip parameters;
- TileLink, TLB/PTW, and virtual memory;
- DMA tracker and stream implementation;
- reservation station and ROB;
- `LoopConv`, im2col, pooling, training, and generic activations;
- mechanical Chisel-to-BSV translation.

BSD source expressions are not copied. If a future change directly derives
source text, the Gemmini copyright notice, conditions, and disclaimer must
accompany it.

## llama.cpp-gemmini

```text
Repository: https://github.com/ajou-aisa/llama.cpp-gemmini
Branch:     develop
Pin:        d5e76be1fca91314c5a0745038b3cedbbdbed13d
License:    MIT
Checkout:   /tmp/aqua-reference/llama.cpp-gemmini
```

Inspected:

- `ggml/src/ggml-gemmini/ggml-gemmini-matmul.cpp`
- `ggml/src/ggml-gemmini/ggml-gemmini-matmul.hpp`
- `ggml/src/ggml-gemmini/ggml-gemmini-args.h`
- `ggml/src/ggml-gemmini/ggml-gemmini.cpp`
- `ggml/src/ggml-quants.c`
- `CMakeLists.txt` and `ggml/src/ggml-gemmini/CMakeLists.txt`
  `GEMMINI_SW_PATH` integration
- `tests/test-gemmini-matmul.cpp`
- `tests/test-gemmini-exsia.cpp`
- `tests/test-gemmini-im2p-routing.cpp`

The pinned repository calls `gemmini_set_tile_ws`, but does not contain its
implementation. CMake resolves `gemmini.h` from an adjacent external
Gemmini software checkout.

Supplemental behavior inspection:

```text
Repository: https://github.com/ajou-aisa/RISC-V-DynDNN-gemmini-include
Commit:     441b550253f0decba974bb8bb5f99535d1db3518
License:    no LICENSE/COPYING file at that commit
Checkout:   /tmp/aqua-reference/gemmini-include
Header:     gemmini.h
```

The supplemental header confirms:

- independent DIM padding;
- double-buffered scratchpad and accumulator partitions;
- initial I/J/K factor bounds;
- scratchpad rows `(I*K + K*J) * DIM`;
- accumulator rows `I*J*DIM`;
- greedy J, then I, then K expansion.

AQuA copies no header source or macros. Checked Rust helpers independently
express the behavior. The supplemental commit is recorded because the
llama.cpp-gemmini pin does not pin that external dependency.

HP1 file-format evidence comes from pinned llama.cpp-gemmini, but canonical
meaning is owned by Rust `Hp1MatrixWeight`. Each block contains 32 int8 codes,
padding, a shared row/channel scale, and either:

- `i16::MIN`, meaning `ZeroBlock`; or
- a nonnegative `LeftShift(u16)`.

Other negative offsets are invalid. This migration uses only the 32-element
block domain; it does not implement HP1 execution.
