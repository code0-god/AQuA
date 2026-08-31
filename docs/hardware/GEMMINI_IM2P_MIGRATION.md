# Gemmini 및 IM2P 마이그레이션 계약

이 문서는 AQuA가 Gemmini와 IM2P.sim에서 어떤 아키텍처 계약을 적용하는지 정의한다. 어느 저장소도 AQuA 소스 트리로 가져오지 않는다.

## 소스 우선순위

충돌은 다음 순서로 해결한다.

1. AQuA Rust 표준 의미론:
   `AQUA_BLOCK_SIZE`, `ActivationExecutionPlan`, ExSIA 스트라이프,
   `ResidualStripe`, RaCo 및 `Hp1MatrixWeight`.
2. IM2P.sim BSV 실행 동작: 스케줄러 핸드셰이크, K 프래그먼트,
   미리보기, 프로바이더 태그 및 순차 완료.
3. Gemmini 메모리 및 루프 아키텍처: 로컬 주소, 뱅크형 메모리,
   누산기 동작, 이중 버퍼링 및 컨트롤러 분리.
4. llama.cpp-gemmini 호스트 타일 팩터 정책.

우선순위가 낮은 참조는 AQuA 하드웨어 구조를 변경할 수 있다. 우선순위가 더 높은 수치적 의미를 암묵적으로 변경해서는 안 된다. 타일 선택은 ExSIA가 시작되기 전에 명시적인 `ActivationExecutionPlan`을 생성하며, 이 계획은 표준 Rust 입력의 일부이다. 검증된 서로 다른 계획은 서로 다른 스트라이프 지수와 잔차를 생성할 수 있지만, 각 결과는 선언된 계획에 대해 결정론적으로 유지된다. RTL은 그 경계 이후 스트라이프를 다시 타일링하거나 재그룹화할 수 없다.

## IM2P.sim에서 AQuA로

| IM2P.sim | AQuA | 마이그레이션된 동작 |
|---|---|---|
| `src/control/WorkTypes.bsv` | `AquaWorkTypes.bsv` | 텐서 ID와 타입이 지정된 로컬 주소를 사용하도록 재작성된 디스크립터 및 작업 필드의 의미 |
| `src/control/MatmulScheduler.bsv` | `MatmulScheduler.bsv` | 스트라이프 순서, J 우선 I 순회, 2엔트리 FIFO, 즉시 미리보기, 순차 완료 |
| `src/control/WorkScheduler.bsv` | `WorkScheduler.bsv` | K 진행, 블록 경계 내 프래그먼트, 블록 인덱스, 누산, 1프래그먼트 미리보기 |
| `src/io/HostMemoryTypes.bsv` | `AquaMemoryProtocol.bsv` | 내장된 호스트 포인터나 종류 판별자가 없는 타입 지정 요청/응답 포트 |
| `src/common/Arithmetic.bsv` | 향후 `Arithmetic.bsv` | WS 데이터패스 마이그레이션까지 연기 |
| `src/array/PE.bsv` | 향후 `PE.bsv` | WS 데이터패스 마이그레이션까지 연기 |
| `src/array/InputSkew.bsv` | 향후 `InputSkew.bsv` | WS 데이터패스 마이그레이션까지 연기 |
| `src/array/SystolicArray.bsv` | 향후 `SystolicArray.bsv` | WS 데이터패스 마이그레이션까지 연기 |
| `src/array/SystolicEngine.bsv` | 향후 `SystolicEngine.bsv` | WS 데이터패스 마이그레이션까지 연기 |
| `src/accumulator/Accumulator.bsv` | 테스트 모델 전용 | 프로덕션 상태는 뱅크형 `AccumulatorMem` 사용 |
| `src/vector/VectorUnit.bsv` | 향후 HP1 전용 유닛 | 범용 벡터 스케일링 정책은 마이그레이션하지 않음 |
| `src/core/IM2PCore.bsv` | 분해된 컨트롤러 | 모놀리식 코어는 복사하지 않음 |

고정된 스케줄러 동작은 기계적으로 번역하지 않고 적용한다.

- `MatmulScheduler`에는 active stripe, 한 개의 lookahead stripe,
  2엔트리 completion FIFO가 있다.
- 현재 매크로 M/N 타일 내에서 J 배열 작업이 I 배열 작업보다 먼저 진행된다.
- 비동기 스트라이프는 연속적이고, 서로 겹치지 않으며, 범위 내에 있어야 한다.
- 현재 작업이 실행되는 동안 다음 스트라이프 하나를 준비할 수 있다.
- 스트라이프 완료는 해당 스트라이프의 마지막 작업이 완료된 후에만 방출된다.
- `MatmulScheduler`의 세 좌표는 private `WorkPosition` 하나로 유지되며,
  순수 next-position 함수가 J, I, 매크로 N 순서만 계산한다.
- `WorkScheduler`는 다음을 사용한다.

  ```text
  fragment_count =
      min(array_dim, remaining_k, remaining_in_hp1_block)
  ```

- HP1 블록 경계에서는 전체 행렬 곱셈 누산을 초기화하지 않는다.
- 스케줄러에서 호스트 주소와 포인터 산술을 제거한다.

## Gemmini에서 AQuA로

| Gemmini | AQuA | 마이그레이션된 동작 |
|---|---|---|
| `GemminiConfigs.scala` / `Configs.scala` | `AquaHardwareGeometry` | 배열 차원, 뱅크 구조, 행 너비, 리소스 불변 조건 |
| `LocalAddr.scala` | `AquaLocalAddr.bsv` | 타입이 지정된 로컬 영역, 뱅크 및 행 |
| `Scratchpad.scala`의 `ScratchpadBank` | `Scratchpad.bsv` | 버퍼링된 읽기, 백프레셔, 쓰기 우선순위, 마스크 |
| 스크래치패드 구성 | 분리된 활성화, 가중치 및 HP1 메타데이터 메모리 | 하나의 패킹된 주소 공간 없이 동시 소유권 제공 |
| `AccumulatorMem.scala` | `AccumulatorMem.bsv` | 광폭 뱅크형 상태, 읽기-수정-쓰기 누산, 명시적 중재 |
| `LoopMatmul.scala` | 향후 `AquaLoopMatmul` | 현재/다음 컨텍스트, 메모리 분할, 완료 기반 승격 |
| `LoadController.scala` | `LoadController.bsv` + `LoadStager.bsv` | 활성 작업/요청/reuse 소유권과 검증된 로컬 쓰기 분리 |
| `StoreController.scala` | `StoreController.bsv` | 누산기 읽기, 출력 요청, 확인 응답에 의해 제어되는 완료 |
| `Controller.scala` | 분리된 AQuA 컨트롤러 | 로드, 실행 및 저장 소유권을 계속 분리 |
| 리저베이션 스테이션 / ROB | 연기됨 | 이 마이그레이션 기반의 일부가 아님 |
| DMA / TileLink / TLB | 타입 지정 `ReadPort`/`WritePort` 뒤의 향후 어댑터 | 핵심 계약의 일부가 아님 |

Gemmini의 패킹된 32비트 로컬 주소는 복사하지 않는다. 현재 AQuA 주소는
명시적인 영역, 뱅크 및 행만 사용한다. 슬롯은 실제 동시 residency와
할당 충돌 검증이 구현될 때만 다시 도입한다.

로드 경계는 네 개의 독립적인 activation, weight, block-scale, row-shift
read port다. `LoadController`가 유일한 활성 `ProviderLoadWork`와 채널별
offered/pending 상태를 소유한다. 각 채널은 single-outstanding이지만 서로
독립적으로 진행한다. 응답은 요청 소비 다음 사이클부터만 허용되며,
`LoadStager`가 태그, 영역, 범위와 메타데이터 마스크를 검증한 뒤 쓴다.

HP1 block-scale과 row-shift는 스칼라가 아니라 J 열별 lane 벡터다. 부분
J 작업의 마스크는 비활성 lane과 `ZeroBlock` 값을 보존한다. 활성값/가중치
스크래치패드의 bank/row 기하와 누산기 bank 기하는 독립적이다.

## llama.cpp-gemmini 호스트 선택

고정된 llama.cpp-gemmini 트리는 `gemmini_set_tile_ws`를 호출하지만, 구현은 `GEMMINI_SW_PATH`를 통해 외부 `gemmini.h`에서 제공된다. AQuA는 관찰된 동작을 검증된 Rust로 재작성한다.

1. M, N, K를 각각 독립적으로 `array_dim`에 맞춰 패딩한다.
2. 이중 버퍼링된 스크래치패드 및 누산기 용량을 계산한다.
3. 패딩된 차원과 리소스 경계로부터 초기 I, J, K 팩터를 선택한다.
4. J, I, K 순으로 확장을 반복 시도한다.
5. 더 이상 어떤 팩터도 확장할 수 없으면 중단한다.

행 계약은 다음과 같다.

```text
scratchpad_rows = (tile_i * tile_k + tile_k * tile_j) * array_dim
accumulator_rows = tile_i * tile_j * array_dim
```

AQuA는 활성화, 가중치, HP1 메타데이터, 누산기 및 전체 논리 K ExSIA 슬롯 제약 조건을 추가한다. LayerNorm 및 Softmax 특수 사례는 제외한다.

## 소유권 게이트

| 질문 | 소유자 |
|---|---|
| 누가 타일 팩터를 선택하는가? | Rust 호스트/런타임 `AquaTileSelector` |
| 누가 현재 BSV 매크로 N을 순회하는가? | RTL `MatmulScheduler` |
| 누가 매크로 M/K 및 컨텍스트를 순회하는가? | 아직 없음; 향후 RTL `AquaLoopMatmul` |
| 누가 K 프래그먼트를 선택하는가? | RTL `WorkScheduler` |
| 누가 ExSIA 스트라이프 행을 결정하는가? | 타일-I 팩터에서 파생되어 ExSIA 전에 `ActivationExecutionPlan`에 고정되는 `AquaTilePlan` |
| 누가 현재 로컬 base/destination을 제공하는가? | `ProviderLoadWork`/`StoreWork`를 만드는 상위 계층 |
| 누가 base 내부의 주소를 도출하는가? | 로드 및 저장 컨트롤러 |
| 누가 외부 요청을 처리하는가? | 타입 지정 read/write port를 연결하는 프로바이더 어댑터 |
| 물리적 DMA는 어디에 연결되는가? | 향후 단계에서 타입 지정 포트 뒤 |

순회 권한은 서로 겹치지 않는다.

- Rust `AquaTileSelector`는 매크로 M/N/K 후보와 용량을 선택한다.
- `MatmulScheduler`는 스트라이프와 매크로 N을 DIM 경계 내 배열 작업으로
  확장하며, J가 가장 안쪽이고 I가 그 다음이다.
- 현재 `ArrayWork`는 전체 논리 K를 전달한다. `WorkScheduler`는 HP1
  블록을 넘지 않도록 그 범위를 프래그먼트로 나눈다.
- 향후 `AquaLoopMatmul`이 실제 매크로 K 범위, 슬롯, 컨텍스트 승격을
  함께 구현하기 전에는 해당 필드나 상태를 BSV 계약에 추가하지 않는다.

## 명시적인 비목표

이는 Gemmini 복제품이 아니다.

이는 Chisel에서 BSV로의 줄 단위 번역이 아니다.

이 마이그레이션에서는 RoCC, RocketChip 매개변수, TileLink, TLB/PTW,
가상 메모리, 물리적 DMA, 리저베이션 스테이션, ROB, Gemmini ISA,
TilerFSM 번역, 컨볼루션, im2col, 풀링, 출력 고정형
데이터패스, 학습 지원 및 범용 활성화 하드웨어를 제외한다.
