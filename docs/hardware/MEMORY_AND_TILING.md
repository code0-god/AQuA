# AQuA 메모리 및 타일링 아키텍처

## 논리 행렬

```text
활성값:              A[M, K]
GGUF 가중치 원본:    W_source[J, K]
행렬 엔진 관점:      W[K, J]
출력:                C[M, J]
```

Rust는 출력 열에 `n`을 사용한다. BSV 디스크립터는 다이어그램에서 J로
표기한 경우에도 동일한 논리 차원을 사용한다.

## 서로 다른 다섯 단위

### 물리 배열 차원

`array_dim`은 물리적 행 및 열 개수이다. 한 번의 일반적인 배열
실행은 최대 `array_dim`개의 K 원소와 `array_dim`개의 출력
열을 처리한다.

### 매크로 타일

호스트가 선택한 계수는 `array_dim` 너비의 행렬 개수를 나타낸다.

```text
macro_m_rows     = tile_i_factor * array_dim
macro_n_columns  = tile_j_factor * array_dim
macro_k_elements = tile_k_factor * array_dim
```

논리 행렬의 가장자리에서는 부분 범위가 생길 수 있다.

### ExSIA 스트라이프

```text
stripe_rows = min(macro_m_rows, remaining logical M)
```

ExSIA 스트라이프는 실행 컨텍스트이지 ExSIA 구성이 아니다. 현재의
표준 Rust ExSIA 참조 구현은 스트라이프의 모든 논리 K 원소를 처리한다.
따라서 ExSIA 용량에는 매크로 K가 아니라 전체 논리 K를 사용한다.

### 배열 작업

하나의 배열 작업 항목은 물리 차원으로 제한된다.

```text
work_i_rows    <= array_dim
work_j_columns <= array_dim
```

매크로 M/J 타일은 하나 이상의 배열 작업을 포함한다.

### K 프래그먼트 및 HP1 블록

HP1 블록 하나는 32개의 K 원소를 소유한다. 물리적 K 프래그먼트는 해당
경계를 넘어서는 안 된다.

```text
remaining_logical_k = work_k_end - k_start
remaining_in_block  = 32 - (k_start % 32)

k_fragment_count =
    min(array_dim, remaining_logical_k, remaining_in_block)
```

Rust 타일 계획의 `k_tile_elements`는 32를 초과할 수 있다. 그러나 현재
BSV에는 매크로 K 식별자나 순회 상태가 없다. `MatmulScheduler`가 만든
`ArrayWork`는 전체 논리 K 범위를 전달하고, `WorkScheduler`는 그 범위를
블록 경계로 제한된 프래그먼트로 분해한다.

## 계층 구조

```text
매크로 M 타일
└── ExSIA 스트라이프

매크로 N/J 타일
└── 하나 이상의 array_dim 너비 배열 작업

현재 BSV의 전체 논리 K 범위
└── 하나 이상의 HP1 블록
    └── 하나 이상의 배열 차원 제한 K 프래그먼트
```

Rust는 계속 매크로 K 후보를 선택하고 용량을 계산한다. 이를 실제 BSV
순회 계약으로 연결하는 작업은 `AquaLoopMatmul` 구현과 함께 연기되어 있다.

## 리소스 인식 호스트 계획

`AquaHardwareGeometry`는 다음을 기술한다.

- 물리 배열 차원;
- 서로 독립적인 활성값 및 가중치 스크래치패드 뱅크와 행;
- 독립적인 HP1 block/row metadata depth와 LEFT/RIGHT shift width;
- `array_dim`과 같은 누산기 뱅크 수 및 뱅크별 행;
- ExSIA 슬롯 개수와 바이트;
- 활성값, 가중치 및 누산기 원소 너비;
- 독립적인 이중 버퍼 활성화 여부.

`AquaTileSelector`는 Gemmini의 J, I, K 순서 탐욕적 확장 방식을 유지하되
모든 후보를 모든 AQuA 리소스에 대해 검사한다.

명시적인 HP1 메타데이터 용량이 필요한 이유는 `Hp1MetaMem`이
`Scratchpad.bsv`의 weight instance와 물리적으로 분리되어 있기 때문이다.
메타데이터는
가중치 코드 저장소의 명시되지 않은 잔여 공간을 사용할 수 없다.

`Hp1MetaMem`의 한 block-scale entry는 J 열마다
`Hp1BlockScale#(blockShiftWidth)` 하나를 갖는 `array_dim` lane 벡터다.
각 lane은 `zeroBlock` 1 bit와 block LEFT-shift magnitude를 직접 보존하므로
encoded width는 `1 + blockShiftWidth`다. 한 row-shift entry는 J 열마다
`UInt#(rowShiftWidth)` 하나를 갖고 row RIGHT-shift magnitude를 직접
보존한다. 부분 J 응답의 마스크는 요청한 열만 갱신하고 비활성 lane을
보존한다.

Rust와 BSV는 다음 depth 단위를 공유한다.

```text
j_groups = ceil(n_tile_columns / array_dim)
block metadata entries = ceil(k_tile_elements / 32) * j_groups
row metadata entries   = j_groups
```

Rust의 required metadata byte 계산은 논리 J 열 수를 사용한다.

```text
block bits = ceil(k_tile_elements / 32)
             * n_tile_columns
             * (1 + hp1_left_shift_bits)
row bits   = n_tile_columns * hp1_row_right_shift_bits
bytes      = ceil((block bits + row bits) / 8)
```

`Hp1MetaGeometry`의 block/row entry depth와 두 width는 BSV elaboration
parameter와 같은 물리 기하를 표현하며, 물리 byte capacity도 이 값에서
checked arithmetic으로 파생된다.

BSV 최상위 매개변수는 다음 기하를 서로 독립적으로 전달한다.

```text
activationBanks / activationRows
weightBanks     / weightRows
accumulatorBanks / accumulatorRows
blockMetaEntries / rowMetaEntries
blockShiftWidth / rowShiftWidth
```

`AquaLocalAddr`의 고정 주소 폭 때문에 각 bank count는 최대 256, 각 row
count와 두 metadata entry count는 최대 65,536이다. controller elaboration은
이 범위를 정적으로 검사한다.

활성값과 가중치는 같은 뱅크 수나 깊이를 가질 필요가 없다. 반면 현재 첫
하드웨어 계약은 출력 J lane마다 하나의 누산기 bank를 사용하므로
`accumulator_banks == array_dim`을 요구한다. logical J를 modulo bank와
folded row로 바꾸는 bank folding은 구현하지 않는다.

`AquaTilePlan`은 선택된 계수, 구체적인 논리 범위, 패딩된 K,
그리고 리소스 사용량을 유지한다. 해당 스트라이프 행은 기존의 검증된
`ActivationExecutionPlan`을 생성한다. `FixedStripePlanner`는 별도의
통합/테스트 정책으로 유지된다.

선택된 스트라이프 계획은 표준 ExSIA 실행 전에 고정된다. 따라서 하드웨어
기하 구조는 명시적인 수치 실행 컨텍스트를 선택하며, ExSIA 그룹화를
내부적으로 변경하지 않는다. 서로 다른 기하 구조로 형상을 다시 실행하면
서로 다른 유효 계획이 선택되어 표준 스트라이프 결과도 달라질 수 있다.
동일한 기하 구조와 형상으로 다시 실행하면 반드시 동일한 계획이 선택되어야
한다.

## RTL 생성과 물리 합성

현재 gate는 positive Bluesim, expected-failure, assertions-disabled safety
test와 대표 top의 BSC Verilog 생성을 포함한다. 이 결과는 RTL elaboration과
생성을 검증하지만 물리 FPGA synthesis를 검증하지 않는다. BRAM inference,
LUT/DSP 사용량, timing/Fmax 및 post-synthesis area는 아직 측정하지 않았다.

## 메모리 수명

| 메모리 | 의미 | 수명 |
|---|---|---|
| `Scratchpad` 활성값 인스턴스 | 클리핑된 활성값 Q 값 | 현재 예약된 로드/실행 범위 |
| `Scratchpad` 가중치 인스턴스 | HP1 코드 행 | 현재 예약된 J/K 프래그먼트 |
| `Hp1MetaMem` | 블록 왼쪽 시프트 및 행 스케일 메타데이터 | 해당 J/K 타일 동안 |
| `AccumulatorMem` | 향후 조밀 및 RaCo 기여값 | 출력 타일이 완료될 때까지 |

`ExsiaStripeMem`과 잔차 패킷 메모리는 아직 프로덕션 BSV 트리에 없다.
Rust의 ExSIA 용량 계산은 유지되지만 BSV 로컬 슬롯 계약을 의미하지 않는다.

## 로컬 메모리 영역

현재 컨트롤러는 상위 계층에서 받은 타입 지정 base/destination 주소에서
오프셋을 산출한다.

```text
AquaLocalAddr {
    region,
    bank,
    row
}
```

활성값, 가중치, HP1 메타데이터, 누산기, ExSIA 스트라이프 및 향후 RaCo
영역은 논리적으로 구분된 상태로 유지된다. 뱅크형 활성값 및 가중치 메모리는
다음을 사용한다.

```text
bank     = global_row % bank_count
bank_row = global_row / bank_count
```

`LoadController`는 activation row와 weight J row의 순서를 각각 전달받은
base 주소에 더하고, 각 메모리의 독립적인 bank count로 선형 주소를
`bank,row`에 매핑한다. HP1 메타데이터와 누산기는 별도 region과 destination을
사용한다. 프로바이더는 로컬 목적지를 선택하거나 다시 작성하지 않는다.

현재 주소에는 슬롯이 없고 이중 버퍼 residency를 주장하지 않는다. 실제로
두 컨텍스트가 동시에 서로 다른 로컬 범위를 점유하고, 할당 충돌과 승격을
검증하는 `AquaLoopMatmul`이 구현될 때만 슬롯 식별자를 다시 도입한다.

## 스크래치패드 동작

표준 인터페이스는 다음을 명시한다.

- 읽기 요청 수락 후 정의된 지연 시간에 응답;
- 소비될 때까지 유지되는 하나의 버퍼링된 응답;
- 백프레셔;
- 단일 포트에서 읽기 수락보다 높은 쓰기 우선순위;
- 선택되지 않은 레인을 보존하는 레인 마스킹 쓰기;
- 시뮬레이션 경계 검사.

첫 번째 물리 백엔드는 BSC가 지원하는 레지스터 또는 BRAM 저장소를 사용할
수 있다. 인터페이스는 교체 가능한 상태로 유지된다.

## 누산기 동작

누산기 뱅크는 출력 열 레인에 매핑된다. 행은 로컬 출력 행에 매핑된다.

```text
accumulate = False: new_value = contribution
accumulate = True:  new_value = old_value + contribution
```

산술은 매개변수화된 누산기 타입을 사용한다. 이 기반에는 암묵적인
너비 축소, 포화, 조밀/RaCo 중재 또는 행 오른쪽 시프트 유닛이 없다.

## 프로바이더 경계

```text
LoadController
    활성 작업, 재사용 key, 채널별 offered/pending 상태
        ├── activation ReadPort
        ├── weight ReadPort
        ├── block-scale ReadPort
        └── row-shift ReadPort
                    ↓
        현재는 시뮬레이터 프로바이더
        향후에는 물리 DMA 어댑터
                    ↓
LoadStager
    태그, 영역, 범위, 마스크 검증 후 로컬 메모리 쓰기
```

네 read port는 포트와 응답 payload 타입으로 채널을 구분한다.
`AquaMemoryKind` 또는 공용 destination 판별자는 없다. 공통
`AquaMemoryTag`는 job, stripe, array-work, fragment, transaction 및
로컬 주소를 보존한다.

`LoadController`는 요청을 발행하기 전에 activation/weight base와 work count가
각 메모리의 실제 row depth를 넘지 않는지 검사한다. 따라서 로컬 메모리가
받을 수 없는 요청이 pending 상태로 들어가 응답을 영구히 막지 않는다.
검사는 assertion diagnostic과 독립적인 functional gate로 active state
설치를 차단한다.

각 채널은 동시에 하나의 요청만 outstanding일 수 있지만 서로 독립적으로
진행한다. 요청이 `offered`인 동안에는 응답을 받지 않으며, 프로바이더가
요청을 소비한 뒤 `pending`이 된 다음 사이클부터 정확한 태그의 응답을
받는다. 따라서 latency-0 동일 사이클 응답은 계약이 아니다.

activation과 weight 응답의 마스크는 정확히 `fragmentKCount`개의 선행 lane과
일치해야 한다. 잘못된 data mask는 scratchpad write와 transaction 완료 전에
거부된다.

block-scale과 row-shift 응답은 각각 J 열별 payload 벡터와 마스크를
전달한다. 마스크는 정확히 `jCount`개의 선행 lane과 일치해야 하며,
`LoadStager`는 검증을 통과한 활성 lane만 `Hp1MetaMem`에 쓴다.

가중치 원본 순서는 `[J lane][K fragment]`로 유지된다. 향후 PE 프리로드
어댑터가 타일 로컬 `[K fragment][J lane]` 재정렬을 수행한다. 전체 모델은
절대 전치되지 않는다.

`StoreController`는 원시 누산기 행을 읽고 태그가 지정된 출력 쓰기를
내보낸다. 완료하려면 출력 승인이 필요하다. 행 오른쪽 시프트 산술은 향후
단계로 남는다.

## 연기된 매크로 K 및 중첩 실행

Gemmini의 루프 컨텍스트는 향후 `AquaLoopMatmul`의 필요성을 제시한다.

```text
현재 컨텍스트: 실행 및 저장
다음 컨텍스트: 로드 및 준비
```

현재 기반은 로드, 스케줄, 저장 컨트롤러를 분리하지만 슬롯, 컨텍스트
승격, 동시 이중 버퍼 실행 또는 매크로 K 순회를 표현하지 않는다. 다음
조건이 모두 구현될 때 해당 계약을 다시 도입한다.

- 두 로컬 residency가 실제로 동시에 존재한다.
- 할당 충돌, 완료 기반 승격, backpressure가 검증된다.
- `AquaLoopMatmul`이 매크로 K 범위를 생성한다.
- `ArrayWork.kTileStart/kTileCount`가 그 실제 범위를 전달한다.

순회 계층은 서로 분리된 상태로 유지된다.

```text
Rust AquaTileSelector: 매크로 M/N/K 후보 선택과 용량 검사
MatmulScheduler: 스트라이프와 매크로 N 내부의 J 우선 I 배열 작업
WorkScheduler: 현재 전체 논리 K 범위의 블록 경계 제한 프래그먼트
향후 AquaLoopMatmul: 매크로 K 순회, 슬롯 할당, 컨텍스트 승격
```
