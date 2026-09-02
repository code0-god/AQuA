# AQuA 현재 코드베이스 분석 가이드

> 기준 브랜치: `main`
> 기준 baseline: `5870cc614cf42cc468e603d258ccebf8906853ae`
> 목적: **다음 기능을 구현하기 전에, 현재까지 만들어진 타일링 / 로컬 메모리 / 스케줄러 / 프로바이더 스테이징 기반을 직접 읽고 이해하기 위한 코드 분석 순서**
> 대상: AQuA 구현을 직접 검토하려는 개발자/연구자
> 작성 기준: 현재 구현된 코드만 우선 설명하고, 아직 구현되지 않은 기능은 별도 표시한다.

---

## 0. 이 문서를 어떻게 사용할 것인가

현재 코드베이스를 처음부터 파일 순서대로 읽는 것은 권장하지 않는다.

AQuA의 현재 구현은 크게 두 층으로 나뉜다.

```text
Rust 호스트/런타임 정책
    ↓
AquaHardwareGeometry
    ↓
AquaTileSelector
    ↓
AquaTilePlan
    ↓
ActivationExecutionPlan

BSV 실행 기반
    ↓
AquaMatmulDescriptor
    ↓
MatmulScheduler
    ↓
ArrayWork
    ↓
WorkScheduler
    ↓
KFragment
    ↓
LoadController
    ↓
Provider request/response
    ↓
Scratchpad activation/weight instances / Hp1MetaMem
    ↓
[ Execute datapath는 아직 없음 ]
    ↓
AccumulatorMem
    ↓
StoreController
```

따라서 분석도 이 흐름을 따라가야 한다.

### 권장 원칙

1. **먼저 문서로 용어를 고정한다.**
2. Rust에서 **왜 그 tile 크기가 선택되는지** 본다.
3. BSV에서 **선택된 실행 범위가 어떻게 ArrayWork와 KFragment로 쪼개지는지** 본다.
4. 그 fragment가 **어떤 provider request로 바뀌는지** 본다.
5. response가 **어느 scratchpad/local address로 들어가는지** 본다.
6. 마지막으로 accumulator/store를 본다.
7. 그 후에야 IM2P.sim의 PE/WS SystolicArray를 볼 준비가 된다.

**PE/SystolicArray부터 읽지 않는다.**

현재 코드에서 가장 중요한 미구현 경계는 다음이다.

```text
LoadCompletion
      ↓
[ ExecuteController / PE preload / WS array 미구현 ]
      ↓
AccumulatorMem
      ↓
StoreController
```

---

# 1. 현재 마일스톤 한눈에 보기

현재 브랜치에서 구현된 것은 다음이다.

```text
Rust
├─ AquaHardwareGeometry
├─ resource-aware AquaTileSelector
├─ Gemmini-style J → I → K factor growth
├─ activation / weight / accumulator capacity accounting
├─ HP1 metadata capacity accounting
├─ ExSIA stripe-slot capacity accounting
└─ AquaTilePlan → ActivationExecutionPlan

BSV
├─ typed local memory address
├─ independent activation Scratchpad instance
├─ independent weight Scratchpad instance
├─ Hp1MetaMem
├─ wide checked AccumulatorMem
├─ MatmulScheduler
├─ WorkScheduler
├─ J → I → macro-K → macro-N traversal
├─ block-size-32 K fragment scheduling
├─ single-context AquaLoopMatmul
├─ ExecuteWork / ExecuteCompletion protocol
├─ tagged provider requests
├─ load response staging
├─ metadata reuse
├─ StoreController
├─ final-macro-K-only store
└─ acknowledgement-gated ArrayWork retirement
```

아직 없는 것:

```text
ExecuteController
PE preload/reorder
WS SystolicArray
HP1 dense integer execution
BlockLeftShiftUnit
RowRightShiftUnit
BSV ExSIA
BSV RaCo
resident macro-tile preload
activation / weight reuse
double-buffer execution overlap
physical DMA
AXI / PCIe / DDR adapter
```

즉 현재 코드는 **“데이터를 어떻게 자르고, 어디에 올리고, 어떻게 추적할지”**까지 구현된 상태다.

아직 **“실제로 dot product를 어떻게 계산할지”**는 붙지 않았다.

---

# 2. 반드시 먼저 이해해야 하는 5개의 단위

다음 용어를 혼동하면 이후 코드가 거의 이해되지 않는다.

## 2.1 Physical array dimension

```text
array_dim
```

예:

```text
16
32
64
```

한 번의 물리 배열 작업에서:

```text
I rows <= array_dim
J columns <= array_dim
K fragment <= array_dim
```

을 만족한다.

---

## 2.2 Macro tile

Rust `AquaTileSelector`가 고른 호스트/런타임 수준의 타일이다.

```text
macro M rows     = tile_i_factor × DIM
macro N columns  = tile_j_factor × DIM
macro K elements = tile_k_factor × DIM
```

예:

```text
DIM = 16
tile_i = 4
tile_j = 2
tile_k = 8

macro M = 64
macro N = 32
macro K = 128
```

이 값은 scratchpad와 accumulator 용량에 맞춰 선택된다.

---

## 2.3 ExSIA stripe

현재 계약:

```text
stripe_rows = macro M rows
```

하지만 매우 중요한 차이가 있다.

```text
ExSIA는 스트라이프 내의 전체 논리 K를 처리한다.
```

즉 ExSIA slot capacity 계산은:

```text
stripe_rows × logical K
```

를 기준으로 한다.

```text
stripe_rows × macro K
```

가 아니다.

이 점은 AQuA tiler가 단순 Gemmini tiler가 아닌 이유 중 하나다.

---

## 2.4 ArrayWork

실제 BSV `MatmulScheduler`가 만드는 physical work다.

```text
iCount <= DIM
jCount <= DIM
```

하나의 macro M/N 범위는 여러 `ArrayWork`로 나뉠 수 있다.
각 work는 현재 stripe/macro-N 경계와 실제 매크로 K 범위도 보존한다.

예:

```text
DIM = 16
stripe rows = 33
N tile columns = 20
```

가능한 work:

```text
I 0..15,  J 0..15
I 0..15,  J 16..19

I 16..31, J 0..15
I 16..31, J 16..19

I 32,     J 0..15
I 32,     J 16..19
```

현재 scheduler는 **J → I → macro K → macro N traversal**을 사용한다.

---

## 2.5 KFragment와 HP1 block

공통 아키텍처 상수:

```text
AQUA_BLOCK_SIZE = 32
```

하나의 HP1 block은 K 32개를 소유한다.

`WorkScheduler`는 fragment를 다음과 같이 정한다.

```text
remaining = work_k_end - fragment_start

remaining_in_block =
    32 - (fragment_start % 32)

fragment_count =
    min(
        array_dim,
        remaining,
        remaining_in_block
    )
```

따라서 fragment는 절대로 32-wide HP1 block 경계를 넘지 않는다.

예:

### DIM 16, K=32

```text
K 0..15
K 16..31
```

### DIM 32, K=32

```text
K 0..31
```

### DIM 64, K=64

```text
K 0..31
K 32..63
```

현재 DIM64 loop test는 `macroKTileElements=32`인 두 매크로 K work를 각각
lane 0부터 독립적으로 load/execute한다. 이는 full DIM-wide resident tile의
lane slicing이 아니다.

---

# 3. 1차 독해 — 문서만 읽기

코드를 열기 전에 다음 3개를 먼저 읽는다.

## 3.1 `README.md`

경로:

```text
README.md
```

확인할 부분:

- `구현된 아키텍처`
- crate별 책임
- `AquaTileSelector`와 `FixedStripePlanner` 차이
- ExSIA boundary
- 현재 범위 / 보류된 작업
- 로드맵

특히 다음 문장을 이해한 뒤 코드로 내려간다.

```text
FixedStripePlanner
    = integration/test policy

AquaTileSelector
    = actual hardware-resource policy
```

둘은 같은 planner가 아니다.

GitHub:

[README.md](../../README.md)

---

## 3.2 `docs/hardware/MEMORY_AND_TILING.md`

이 문서는 **현재 BSV/Rust 코드의 용어 사전**이다.

다음 순서로 읽는다.

1. 논리 행렬
2. 서로 다른 다섯 가지 단위
3. 자원 인식형 host 계획
4. 메모리 수명
5. 로컬 메모리 영역
6. scratchpad 동작
7. accumulator 동작
8. provider 경계
9. 보류된 overlap

읽은 뒤 다음 질문에 답할 수 있어야 한다.

- macro tile과 array work의 차이는?
- stripe와 macro-K의 관계는?
- 현재 local base/destination은 누가 제공하고 슬롯은 언제 다시 도입하는가?
- provider가 local address를 정하는가?
- row shift는 현재 어디까지 구현되어 있는가?
- physical DMA는 현재 존재하는가?

정답을 스스로 말할 수 없다면 BSV로 내려가지 않는다.

GitHub:

[MEMORY_AND_TILING.md](MEMORY_AND_TILING.md)

---

## 3.3 `docs/hardware/GEMMINI_IM2P_MIGRATION.md`

이 문서는 **왜 이 코드가 지금 모양인지** 설명한다.

확인:

```text
AQuA Rust semantics
    >
IM2P.sim execution behavior
    >
Gemmini memory/loop architecture
    >
llama.cpp-gemmini tiling policy
```

즉 reference 간 의미가 다르면 위 순서를 따른다.

특히 Ownership Gate를 읽는다.

```text
tile factor 선택:
    Rust AquaTileSelector

현재 stripe / macro N / macro K / J-I traversal:
    RTL MatmulScheduler

현재 macro K fragment:
    RTL WorkScheduler

현재 single-context lifecycle:
    RTL AquaLoopMatmul

ExSIA stripe:
    AquaTilePlan

local base/destination:
    상위 ProviderLoadWork / StoreWork

slot, resident reuse, two-context promotion:
    향후 tile-residency 단계

external memory / physical DMA:
    향후 typed read/write port adapter
```

GitHub:

[GEMMINI_IM2P_MIGRATION.md](GEMMINI_IM2P_MIGRATION.md)

---

# 4. 2차 독해 — Rust hardware geometry

이제 Rust로 내려간다.

## 4.1 `crates/aqua-runtime/src/hardware.rs`

먼저 이 파일을 읽는다.

중심 타입:

```rust
AquaHardwareGeometry
```

필드별 의미를 직접 적어본다.

```text
array_dim

activation_spad_banks
activation_spad_rows_per_bank

weight_spad_banks
weight_spad_rows_per_bank

accumulator_banks
accumulator_rows_per_bank

exsia_slot_count
exsia_slot_bytes

hp1_meta:
    block_entries
    row_entries
    left_shift_bits
    row_right_shift_bits

derived hp1_metadata_capacity_bytes

activation_element_bits
weight_element_bits
accumulator_element_bits

double_buffer_activation
double_buffer_weight
double_buffer_accumulator
```

### 여기서 반드시 확인할 것

#### 1. usable capacity

```rust
usable_rows(rows, double_buffered)
```

double buffering이면 현재 구현은:

```text
usable = rows / 2
```

다.

#### 2. array dimension 제한

현재 geometry validation에서 DIM과 B=32가 서로 나누어떨어지는 관계를 요구한다.

지원 목표:

```text
16
32
64
```

#### 3. accumulator bank validation

현재 첫 하드웨어 계약은 output J lane마다 하나의 accumulator bank를
사용하므로 다음을 요구한다.

```text
accumulator_banks == array_dim
```

bank modulo 및 row folding은 향후 최적화다.

GitHub:

[hardware.rs](../../crates/aqua-runtime/src/hardware.rs)

---

## 4.2 `hardware/builder.rs`

이 파일에서는 단순 builder 문법보다 **default geometry가 무엇인지** 본다.

질문:

- 기본 DIM은 어떤 방식으로 들어가는가?
- activation/weight/accumulator 기본 bank/row는?
- HP1 shift width는?
- ExSIA wide value/exponent/mask width는?
- double-buffer default는?

직접 하나의 geometry 예시를 메모한다.

```text
DIM:
A SPAD:
W SPAD:
ACC:
ExSIA:
HP1 metadata:
double buffer:
```

---

# 5. 3차 독해 — Rust tile capacity 수식

다음 파일:

```text
crates/aqua-runtime/src/tiling/capacity.rs
```

이 파일은 **타일러의 실제 자원 모델**이다.

함수 순서대로 본다.

---

## 5.1 `resource_usage()`

이 함수가 하나의 `TileFactors` 후보에 대해 계산하는 값:

```text
stripe_rows
n_tile_columns
k_tile_elements

activation_spad_rows
weight_spad_rows
hp1_block_metadata_entries
hp1_row_metadata_entries
hp1_metadata_bytes
accumulator_rows_per_bank
exsia_slot_bytes
```

이 구조를 먼저 이해한다.

---

## 5.2 Activation scratchpad

현재 수식:

```text
tile_i × tile_k × DIM
```

row 단위다.

의미:

```text
macro M/K activation residency
```

---

## 5.3 Weight scratchpad

현재 수식:

```text
tile_k × tile_j × DIM
```

의미:

```text
macro K/J weight residency
```

---

## 5.4 Accumulator

현재 수식:

```text
tile_i × tile_j × DIM
```

이는 현재 direct J-lane bank mapping에서 필요한 **뱅크별 row 수**다.
double buffering이면 usable row 수도 각 bank에서 절반이 된다.

---

## 5.5 HP1 metadata

중심 식:

```text
blocks = ceil(k_tile_elements / 32)

block metadata:
    blocks
    × n_tile_columns
    × (1 + hp1_left_shift_bits)

row metadata:
    n_tile_columns
    × hp1_row_right_shift_bits

J groups:
    ceil(n_tile_columns / DIM)

block entries:
    blocks × J groups

row entries:
    J groups
```

추가 1 bit는 `zeroBlock`이다. block LEFT-shift와 row RIGHT-shift width,
그리고 두 memory depth는 서로 독립적이다. HP1 metadata는 weight
Scratchpad와 별도의 capacity다.

---

## 5.6 ExSIA slot

가장 주의해서 본다.

```text
wide:
    stripe_rows
    × logical_k
    × wide_value_bits

metadata:
    stripe_rows
    × ceil(logical_k / 32)
    × (exponent_bits + outlier_mask_bits)
```

여기서는 `k_tile_elements`가 아니라:

```rust
shape.k()
```

를 사용한다.

이유:

```text
ExSIA 표준 스트라이프는 전체 논리 K를 폴딩한다.
```

---

## 학습 체크포인트

다음 질문에 답해본다.

> 왜 weight scratchpad는 macro K를 쓰는데 ExSIA slot은 logical K 전체를 쓰는가?

이 답이 현재 AQuA tiler를 이해하는 핵심이다.

GitHub:

[capacity.rs](../../crates/aqua-runtime/src/tiling/capacity.rs)

---

# 6. 4차 독해 — Tile selector

다음:

```text
crates/aqua-runtime/src/tiling/selector.rs
```

핵심 method:

```rust
AquaTileSelector::select()
```

---

## 6.1 초기 factor

먼저 M/N/K를 DIM 배수로 padding한다.

```text
padded M
padded N
padded K
```

그리고:

```text
matrix_i = padded_m / DIM
matrix_j = padded_n / DIM
matrix_k = padded_k / DIM
```

로 factor 공간을 만든다.

---

## 6.2 초기 accumulator bound

```rust
accumulator_matrices =
    usable_accumulator_rows / DIM

max_i_j =
    integer_sqrt(accumulator_matrices)
```

이 부분은 Gemmini 방식의 초기 I/J 경계다.

---

## 6.3 initial K bound

activation/weight usable rows 중 작은 값을 기준으로 초기 K factor를 잡는다.

이후 AQuA의 추가 리소스 제약 조건을 `reduce_to_feasible()`가 처리한다.

---

## 6.4 `reduce_to_feasible()`

현재 제한 리소스별 감소 순서를 직접 표로 만든다.

예:

```text
Activation scratchpad:
    I 먼저 감소
    그다음 K

Weight scratchpad:
    J 먼저 감소
    그다음 K

Accumulator:
    J 먼저 감소
    그다음 I

Hp1Metadata:
    K 먼저 감소
    그다음 J

ExsiaStripeSlot:
    I 감소
```

여기서 왜 각 축을 줄이는지 생각한다.

---

## 6.5 `grow_factors()`

중요:

```text
J
→ I
→ K
```

순서로 증가를 시도한다.

한 후보가 모든 resource를 만족하는 경우만 채택한다.

즉 이 함수가 Gemmini 호스트 측 증가 동작의 핵심이다.

---

## 6.6 selector를 읽은 뒤 확인할 질문

- `tile_i`가 커지면 어떤 resource들이 증가하는가?
- `tile_j`가 커지면?
- `tile_k`가 커지면?
- 왜 ExSIA capacity는 `tile_i`를 직접 제한하는가?
- HP1 metadata가 K/J를 제한하는 이유는?

GitHub:

[selector.rs](../../crates/aqua-runtime/src/tiling/selector.rs)

---

# 7. 5차 독해 — `AquaTilePlan`

다음:

```text
crates/aqua-runtime/src/tiling.rs
```

읽을 타입:

```rust
MatmulShape
TileFactors
AquaTilePlan
LimitingResource
TilingError
```

가장 중요:

```rust
AquaTilePlan::activation_plan()
```

이 method가:

```text
stripe_rows
```

기준으로:

```text
StripePlan 0
StripePlan 1
...
```

을 생성한다.

즉 현재 수치 흐름은:

```text
hardware geometry
    ↓
tile factors
    ↓
stripe_rows
    ↓
ActivationExecutionPlan
    ↓
canonical ExSIA
```

이다.

따라서 타일링은 성능 최적화만이 아니라 ExSIA 실행 컨텍스트를 결정한다.

GitHub:

[tiling.rs](../../crates/aqua-runtime/src/tiling.rs)

---

# 8. Rust 단계가 끝났는지 확인하는 간단한 연습

임의의 shape를 잡는다.

예:

```text
DIM = 16

M = 33
N = 20
K = 48
```

손으로 다음을 적어본다.

```text
padded M = 48
padded N = 32
padded K = 48

matrix I = 3
matrix J = 2
matrix K = 3
```

그다음 실제 test 또는 작은 debug call로:

```text
tile factors
stripe_rows
n_tile_columns
k_tile_elements
resource usage
```

를 확인한다.

여기까지 이해한 다음 BSV로 넘어간다.

---

# 9. 6차 독해 — 현재 BSV 프로덕션 트리

`hw/bsv/Makefile`의 프로덕션 목록은 정확히 14개다.

```text
hw/bsv/src/
├── common/
│   ├── AquaTypes.bsv
│   ├── AquaWorkTypes.bsv
│   └── AquaMemoryProtocol.bsv
├── control/
│   ├── MatmulScheduler.bsv
│   ├── WorkScheduler.bsv
│   ├── LoadController.bsv
│   ├── StoreController.bsv
│   └── AquaLoopMatmul.bsv
└── memory/
    ├── AquaLocalAddr.bsv
    ├── Scratchpad.bsv
    ├── Hp1MetaMem.bsv
    ├── AccumulatorMem.bsv
    ├── LoadStager.bsv
    └── AquaMemorySubsystem.bsv
```

모듈이 없는 공유 패키지도 목적이 명확하다.

- `AquaTypes`: 공통 scalar와 enum.
- `AquaWorkTypes`: descriptor, stripe, work, fragment, load/store 작업.
- `AquaMemoryProtocol`: 공통 tag, payload, typed port.
- `AquaLocalAddr`: region/bank/row 주소와 순수 bank 매핑.

이들은 독립 state machine이 아니라 여러 모듈이 공유하는 최소 계약이다.

---

# 10. 공통 타입과 주소

`AquaWorkTypes`의 현재 계층은 다음뿐이다.

```text
AquaMatmulDescriptor
    ↓
ActivationStripe
    ↓
ArrayWork
    ↓
KFragment
    ↓
ExecuteWork / ExecuteCompletion
```

`ArrayCount`는 지원 DIM 16/32/64와 부분 edge를 표현한다.
`AquaMatmulDescriptor`의 `macroKTileElements`는 Rust
`AquaTilePlan.k_tile_elements()`와 같은 concrete extent 의미를 가진다.
`ArrayWork`는 stripe/macro-N 경계와 현재 매크로 K의 실제
`kTileStart/kTileCount`를 보존한다.

`AquaLocalAddr`도 세 필드만 가진다.

```text
AquaLocalAddr { region, bank, row }
```

slot field는 없다. 다음이 모두 구현될 때만 다시 도입한다.

1. 두 residency가 실제로 동시에 존재한다.
2. 할당 충돌과 backpressure를 검증한다.
3. 완료 기반 context 승격이 존재한다.
4. `AquaLoopMatmul`이 해당 할당을 소유한다.

---

# 11. `MatmulScheduler.bsv`

private 진행 상태는 하나다.

```text
WorkPosition { macroNStart, macroKStart, iStart, jStart }
```

순수 `nextWorkPosition`은 다음 순서를 보존한다.

```text
같은 macro N에서 J 진행
→ J 종료 후 I 진행, J reset
→ I 종료 후 다음 macro K, I/J reset
→ K 종료 후 다음 macro N, K/I/J reset
→ 모든 work 종료
```

따라서 J가 I보다 먼저 진행된다. partial I/J와 마지막 partial macro N도
같은 함수가 처리한다.

`FullMatrix`는 active stripe와 한 개의 lookahead를 관리한다.
`AsyncStripes` publication은 연속 ID, gap 없음, overlap 없음, M 범위,
계획된 row 수를 검증한다. 마지막 work가 retire된 뒤에만 completion을 낸다.

읽을 테스트:

```text
TbMatmulScheduler.bsv
TbMatmulMacroK.bsv
TbMatmulStripeGap.bsv
TbMatmulStripeOverlap.bsv
TbMatmulStripeOutOfBounds.bsv
```

---

# 12. `WorkScheduler.bsv`

현재 `ArrayWork`의 매크로 K 범위를 다음 식으로 분할한다.

```text
fragment_count = min(array_dim, remaining_k, remaining_in_32_wide_block)
```

fragment는 HP1 block 경계를 넘지 않는다. block 경계는 accumulator reset
경계가 아니다. 현재 fragment 하나와 lookahead 하나를 유지한다.
K range overflow는 diagnostic assertion과 별도로 state 설치 조건에서
검사한다. assertions-disabled RTL safety test는 overflow work가 scheduler
state에 들어가지 않는지 확인한다.

Rust가 선택한 concrete K extent는 descriptor와 `MatmulScheduler`를 통해
`ArrayWork`에 전달된다. `WorkScheduler`는 이 범위를 다시 계산하지 않는다.

## 12.1 `AquaLoopMatmul.bsv`

`AquaLoopMatmul`은 `MatmulScheduler`와 `WorkScheduler`를 내부에 두는
single-context lifecycle coordinator다. 좌표를 독립적으로 계산하지 않고
현재 work/fragment가 만든 identity를 load, execute, store protocol에
부여한다.

```text
load offer → exact LoadCompletion
→ execute offer → exact ExecuteCompletion
→ 다음 fragment
→ final 매크로 K에서만 store
→ exact StoreCompletion 뒤 ArrayWork retirement
```

activation/weight/metadata는 고정 staging 주소를 프래그먼트마다 재사용한다.
누산기 주소는 stripe/macro-N 상대 I/J group으로 계산되어 같은 output work가
서로 다른 매크로 K에서도 같은 cell을 사용한다. execute는 protocol과
testbench executor만 있으며 production PE/WS arithmetic은 없다.

---

# 13. `AquaMemoryProtocol.bsv`

`AquaMemoryTag`는 job, stripe, array-work, fragment, transaction,
local address identity를 보존한다. 채널 종류는 tag가 아니라 포트와 response
payload 타입이 구분한다.

```text
ReadRequestSourceIfc
ReadResponseSinkIfc#(response_t)
ReadPortIfc#(response_t)
```

외부 read port는 네 개다.

```text
activationPort  → ActivationMemoryResponse
weightPort      → WeightMemoryResponse
blockShiftPort  → BlockShiftMemoryResponse
rowShiftPort    → RowScaleMemoryResponse
```

요청 형식은 공유하지만 응답 payload는 다르다. 공용 kind 판별자와
queued-response API는 없다. output은 typed write request와 ack를 사용한다.

---

# 14. `LoadController.bsv`

`LoadController`만 active `ProviderLoadWork`를 소유한다. 네 채널은 각각
`offered request`와 `pending tag`를 가진다. 채널마다 single-outstanding이지만
서로 독립적으로 진행한다.

schedule 시 activation/weight base에서 마지막 work row까지 계산하고 실제
`activationRows`/`weightRows` 안에 있는지 확인한다. 인코딩 폭만 맞고 물리
depth를 넘는 work는 request를 발행하기 전에 거부한다.
전체 work validity는 assertion과 독립적인 functional gate로 active state
설치를 제어한다.

```text
request offered
→ provider consumes request
→ pending tag installed
→ 다음 cycle부터 exact response 가능
```

request consumption 전 response는 거부한다. latency-0 동일 cycle response는
계약이 아니다. 소비 후 한 사이클 이상 지연된 정확한 tag response는 허용된다.

논리 범위:

```text
activation: outer I row, inner K fragment
weight:     outer J row, inner K fragment  (W_source[J, K])
block:      outer J lanes, inner block index
row shift:  outer J lanes, inner 0
```

row-shift reuse key는 job/tensor/J range/destination을 포함한다. block-scale
reuse key는 여기에 block index와 destination을 더한다. J, block 또는
목적지가 바뀌면 reload한다.

---

# 15. `LoadStager.bsv`와 HP1 metadata

`LoadStager`는 active work를 소유하지 않는다. 다음을 검증한 뒤에만 쓴다.

1. 해당 response가 outstanding인가?
2. 전체 tag가 pending tag와 일치하는가?
3. region/bank/row가 맞는가?
4. activation/weight mask가 `fragmentKCount`와 일치하는가?
5. metadata mask가 `jCount`와 일치하는가?

wrong job/stripe/work/fragment/transaction/address response는 write를 만들지 않는다.

metadata response는 J별 vector다.

```text
block scale: mask + Vector#(arrayDim, Hp1BlockScale)
row shift:   mask + Vector#(arrayDim, UInt#(shiftWidth))
```

앞의 `jCount` lane만 활성이다. `Hp1MetaMem`은 활성 lane만 갱신하고 나머지는
보존한다. 서로 다른 J 열 값과 `ZeroBlock` lane도 그대로 유지한다.

읽을 테스트:

```text
TbHp1MetaMem.bsv
TbAquaMemorySubsystem.bsv
TbActivationLoadDepthOverflow.bsv
TbWeightLoadDepthOverflow.bsv
TbActivationResponseMaskMismatch.bsv
TbWeightResponseMaskMismatch.bsv
TbMetadataResponseMaskMismatch.bsv
```

---

# 16. `Scratchpad.bsv`와 독립 geometry

공통 bank 구현과 bank vector 구현은 `Scratchpad.bsv` 하나에 있다.
`LoadStager`가 activation과 weight instance를 독립적으로 만든다.

```text
activationBanks / activationRows / activationWidth
weightBanks     / weightRows     / weightWidth
accumulatorBanks / accumulatorRows / accumulatorWidth
```

세 기하는 서로 독립이다. masked scratchpad write는 비활성 lane을 보존한다.
read response는 소비될 때까지 유지되며 write가 같은 port의 accepted read보다
우선한다.

`AccumulatorMem`은 overwrite와 checked accumulate를 구분한다. overflow는
assertion으로 진단하는 동시에 functional gate가 pending write와 completion을
막아 저장값을 보존한다. accumulator bank count도 DIM이나 scratchpad bank
count에 묶이지 않는다.

---

# 17. `StoreController.bsv`와 최상위 wiring

`StoreController`는 accumulator row를 읽고 output write request를 만든다.
request consumption만으로 완료하지 않는다. 정확한 acknowledgement 이후에만
다음 row 또는 `StoreCompletion`으로 진행한다.

`AquaMemorySubsystem` 연결:

```text
AquaLoopMatmul
    ├── ProviderLoadWork ────────────────┐
    ├── ExecuteWork / completion         │ testbench/future executor
    └── final-K StoreWork ───────────┐   │
                                    ↓   ↓
LoadController requests ─────────────→ four typed read ports
LoadController pending tags
                                      provider responses
                                               ↓
LoadStager ─→ activation/weight Scratchpad + Hp1MetaMem

AccumulatorMem → StoreController → typed output request / ack
```

최상위는 activation, weight, metadata, accumulator geometry를 각각 전달한다.

---

# 18. 현재 BSV에서 없는 것

- arithmetic, PE, input skew, WS systolic array;
- ExecuteController;
- BSV ExSIA와 RaCo datapath;
- HP1 integer/left-shift/right-shift unit;
- resident macro-tile preload와 activation/weight reuse;
- slot allocation과 double-buffer overlap;
- DIM64 resident tile lane slicing;
- physical DMA, TileLink, AXI, PCIe, DDR adapter;
- accelerator-resident intermediate tensor.

future contract 재도입 조건은 항상 같다.

```text
실제 동작 + 명확한 state owner + boundary validation + regression/synthesis evidence
```

---

# 19. 테스트와 검증

positive simulation top 19개:

```text
mkTbHardwareContracts
mkTbHp1MetaMem
mkTbLocalAddr
mkTbScratchpadBank
mkTbAccumulatorMem
mkTbAccumulatorBankGeometry
mkTbWorkScheduler
mkTbMatmulScheduler
mkTbMatmulMacroK
mkTbAquaLoopMatmul
mkTbAquaLoopMatmulDim32
mkTbAquaLoopMatmulDim64
mkTbAquaLoopMatmulAsync
mkTbAquaLoopAccumulatorMapping
mkTbMockAquaProvider
mkTbLoadController
mkTbStoreController
mkTbAquaMemorySubsystem
mkTbLoopMatmulMemoryIntegration
```

expected-failure top 19개:

```text
mkTbAccumulatorOverflow
mkTbInvalidAccumulatorBankGeometry
mkTbMatmulStripeGap
mkTbMatmulStripeOverlap
mkTbMatmulStripeOutOfBounds
mkTbMatmulInvalidDescriptor
mkTbMatmulInvalidMacroKZero
mkTbMatmulInvalidMacroKLarge
mkTbMatmulWrongStripeId
mkTbLoopWrongLoadCompletion
mkTbLoopWrongExecuteCompletion
mkTbLoopWrongStoreCompletion
mkTbHp1BlockDepthOverflow
mkTbHp1RowDepthOverflow
mkTbActivationLoadDepthOverflow
mkTbWeightLoadDepthOverflow
mkTbActivationResponseMaskMismatch
mkTbWeightResponseMaskMismatch
mkTbMetadataResponseMaskMismatch
```

assertions-disabled RTL safety top 6개:

```text
mkTbLoadInvalidWorkGate
mkTbStoreInvalidWorkGate
mkTbAccumulatorOverflowGate
mkTbWorkRangeOverflowGate
mkTbMatmulInvalidInputGate
mkTbLoopInvalidCompletionGate
```

BSC RTL generation top 4개:

```text
mkMemorySynthTop
mkSchedulerSynthTop
mkMemorySubsystemSynthTop
mkLoopMatmulSynthTop
```

이 top들은 BSC Verilog 생성까지 검증한다. BRAM inference, LUT/DSP 사용량,
timing/Fmax 및 post-synthesis area를 포함하는 물리 FPGA synthesis는 아직
검증하지 않았다.

```bash
make -C hw/bsv bsv-test-one TOP=mkTbMatmulScheduler
make -C hw/bsv bsv-test-one TOP=mkTbAquaLoopMatmul
make -C hw/bsv bsv-test-one TOP=mkTbLoopMatmulMemoryIntegration
make -C hw/bsv bsv-test-one TOP=mkTbLoadController
make -C hw/bsv bsv-test-one TOP=mkTbAquaMemorySubsystem
make -C hw/bsv bsv-test-no-assert
make -C hw/bsv verify
```

검증할 핵심은 J-before-I-before-macro-K-before-macro-N, partial edge,
block-bounded K, fragment-local DIM16/32/64 실행, exact completion matching,
final-K-only store, output ack retirement, async stripe lifecycle, consume 전
response rejection, delayed exact response, wrong-tag 차단, channel independence,
metadata reuse/vector 보존, masked write와 checked overflow다.

---

# 20. 추천 독해 순서

```text
README / hardware docs
→ Rust hardware geometry와 tiler
→ AquaTypes / AquaWorkTypes
→ MatmulScheduler / WorkScheduler
→ AquaLoopMatmul
→ AquaMemoryProtocol / AquaLocalAddr
→ LoadController / LoadStager
→ Scratchpad / Hp1MetaMem / AccumulatorMem
→ StoreController / AquaMemorySubsystem
→ testbenches / Makefile / synthesis tops
```

삭제된 wrapper/router 경로를 현재 독해 순서에 넣지 않는다.

---

# 21. 이해 체크리스트

- [ ] `WorkPosition`과 J → I → macro K → macro N 순서를 설명할 수 있는가?
- [ ] Rust `k_tile_elements`와 BSV `macroKTileElements`의 같은 의미를 설명할 수 있는가?
- [ ] 매크로 K와 fragment-local staging/residency를 구분할 수 있는가?
- [ ] load/execute/store completion identity와 final-K retirement를 설명할 수 있는가?
- [ ] 네 typed port, offered/pending, next-cycle response를 설명할 수 있는가?
- [ ] channel별 single-outstanding과 채널 간 독립성을 설명할 수 있는가?
- [ ] metadata reuse key와 J별 vector mask를 설명할 수 있는가?
- [ ] `ZeroBlock`과 비활성 lane 보존을 설명할 수 있는가?
- [ ] activation/weight/accumulator geometry 분리를 설명할 수 있는가?
- [ ] 왜 store completion이 acknowledgement를 기다리는가?
- [ ] slot, double buffering, resident tile reuse, arithmetic, DMA가 아직 없음을 아는가?

---

# 22. 마지막 핵심 그림

```text
Rust AquaHardwareGeometry / AquaTileSelector
                ↓
AquaTilePlan / ActivationExecutionPlan
                ↓
BSV AquaMatmulDescriptor
                ↓
MatmulScheduler ── ArrayWork: J → I → macro K → macro N
                ↓
WorkScheduler ─── block-bounded KFragment
                ↓
AquaLoopMatmul ── load → execute protocol → final-K store
                ↓
LoadController ─ four typed single-outstanding ports
                ↓ provider, next-cycle-or-later response
LoadStager ────── activation/weight Scratchpad + Hp1MetaMem vectors

[fragment-local staging; arithmetic / PE / WS array / ExSIA / RaCo: deferred]

AccumulatorMem → StoreController → output request / acknowledgement
```

현재 단순화의 핵심은 매크로 K 제어를 resident tile reuse나 실제 arithmetic
완료로 과장하지 않는 것이다.
