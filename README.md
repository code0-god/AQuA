# AQuA

**적응형 양자화 가속기**

AQuA는 하드웨어 네이티브 적응형 양자화를 트랜스포머 실행에 통합하는 엔드투엔드 LLM 가속기를 목표로 한다. 현재 마일스톤은 CPU-shadow Candle 통합, 결정론적 Rust ExSIA 및 RaCo 참조 구현, 프로파일 안전 Q8_HP1 로딩, 정규 정수 가중치 추출과 함께, 리소스를 고려하는 타일러 및 실행 가능한 BSV 로컬 메모리, 스케줄러, 공급자 스테이징 기반이다.

## 구현된 아키텍처

```text
Candle Tensor
       |
       v
Device::Aqua / AquaStorage
       |
       +---------------- 지원되지 않는 연산 --> Candle CPU 폴백
       |
       `---------------- 지원되는 부동소수점 matmul
                                |
                                v
      정확한 논리 레이아웃 구체화
               |
               v
       정규 F32 HostTensor
               |
               v
 FixedStripePlanner (통합 정책 전용)
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
 밀집 I4/I8/I16                 ResidualStripe
        |                       로컬 행 / K / i32
        |                             |
        |                             v
        |                    Rust RaCo 참조 구현
        |                             |
        |                  +----------+----------+
        |                  |          |          |
        |                  v          v          v
        |              균형형      압축된 K   활성 레인
        |               기수
        |                  \          |          /
        |                   \         |         /
        |                    v        v        v
        |                       정수 내적
        |                            |
        |                            v
        |                       기수 합성
        |                            |
        |                            v
        |                    원시 정수 보정
        |
        v
 dequantize_dense: q * 2^theta
        Q 전용 손실 재구성
               |
               v
        Candle CPU matmul
               |
               v
 Device::Aqua CPU-shadow 결과
```

구현된 크레이트의 역할은 다음과 같다.

* `aqua-protocol`: Candle과 독립적인 텐서 및 프로토콜 의미 체계.
* `aqua-runtime`: 정규 F32 `HostTensor`, 검증된 활성화 행렬 및 스트라이프 계획 기하 구조, 검증된 하드웨어 용량, 결정론적인 리소스 인식 매크로 타일 선택.
* `aqua-exsia`: ExSIA 전용 계약, 정규 순차 참조 구현, 공개 밀집 Q 전용 역양자화. `dequantize_dense`는 의도적으로 잔차 이벤트를 무시하며 잔차 인식 재구성이 아니다.
* `aqua-raco`: 결정론적 부호 있는 21비트 균형형 기수 분해, 정규 너비 32 블록/K 및 활성 레인 압축, 밀집 정수 가중치 코드 실행, 기수 합성, 원시 정수 보정. 공개 읽기 전용 단계 계약은 BSV 골든 비교에 적합하다.
* `aqua-weight`: Candle과 독립적인 Q8_HP1 원시 블록 파싱, 정규 `[row][K]` 정수 코드, 블록별 좌측 시프트, 정확한 행 스케일 지수, 결정론적 역할 분류, 레지스트리, 모델 통계.
* `aqua-candle`: 프레임워크 어댑터, 통합 전용 `FixedStripePlanner`, `DenseQOnlyAquaExecutor`, GGUF 가중치 캡처 실행기, `Device::Aqua` 팩토리.
* `third_party/candle`: AQuA Candle 포크. 기능 플래그로 제어되는 Aqua 백엔드는 CPU 섀도를 저장하고, 프로파일로 식별된 GGUF 파일에서만 Q8_H 숫자 ID를 디코딩하며, 주입된 실행기에 원시 GGUF 텐서를 노출하고, 일반 CPU 실행으로 폴백한다.
* `aqua-host`: 호스트 경계 스모크 실행 파일, `inspect-hp1` 모델 검사 및 정규 동등성 명령.
* `hw/bsv`: BSC로 검사된 뱅크형 활성화/가중치/HP1/누산기 메모리, 타일형 matmul 및 블록 경계 K 스케줄러, 태그가 지정된 공급자 로드/스토어 스테이징, Bluesim 계약 테스트, 대표 RTL 생성.

### BSV 실행 기반

현재 프로덕션 BSV 트리는 구현된 기반만 표현하는 13개 패키지다.

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
│   └── StoreController.bsv
└── memory/
    ├── AquaLocalAddr.bsv
    ├── Scratchpad.bsv
    ├── Hp1MetaMem.bsv
    ├── AccumulatorMem.bsv
    ├── LoadStager.bsv
    └── AquaMemorySubsystem.bsv
```

`MatmulScheduler`는 스트라이프 안에서 J를 I보다 먼저 진행하고 매크로 N
경계에서 I를 다시 시작한다. `WorkScheduler`는 현재 `ArrayWork`의 논리 K
범위만 32-wide HP1 블록 경계를 넘지 않는 프래그먼트로 나눈다.

RTL의 매크로 K 순회는 아직 구현되지 않았다. 현재 BSV 스케줄러는 하나의
명시적인 전체 논리 K 범위를 사용하고, `WorkScheduler`가 이를 DIM 및
32-element 블록 경계 프래그먼트로 분할한다. Rust의 `k_tile_elements`는
리소스 인식 계획에 계속 포함되며, `AquaLoopMatmul`이 추가될 때 실제 RTL
실행 경계가 된다.

`LoadController`는 활성 작업과 네 개의 독립적인 활성값, 가중치, block-scale,
row-shift 단일 outstanding 채널을 소유한다. 각 채널은 종류 판별자가 없는
타입 지정 요청/응답 포트다. 공급자는 요청을 소비한 다음 사이클부터만 응답할
수 있으며, `LoadStager`는 태그, 로컬 영역, 범위, 메타데이터 마스크를 검증한
뒤에만 쓰기를 수행한다.

HP1 scaling은 부동소수점 weight scale 대신 방향이 명시된 정수 메타데이터를
직접 저장한다. block metadata는 `zeroBlock`과 block-level LEFT shift를,
row metadata는 row-level RIGHT shift를 보존한다. 두 메모리는 독립적인
depth와 width를 가지며, 부분 J 작업은 비활성 레인을 보존한다. 활성값 및
가중치 스크래치패드의 뱅크/행 기하는 독립적이지만, 현재 첫 하드웨어 계약의
누산기 뱅크 수는 `array_dim`과 같고 bank folding은 구현하지 않는다.

현재 BSV 주소와 작업 계약에는 슬롯, 이중 버퍼 컨텍스트 또는 매크로 K
식별자가 없다. 실제 동시 residency와 `AquaLoopMatmul` 매크로 K 순회가
구현될 때 해당 상태와 검증을 함께 다시 도입한다.

`tensor_to_host`는 임의의 Candle 장치에 있는 지원되는 부동소수점 텐서를 CPU로 복사하고, F32로 변환하며, 논리 레이아웃을 연속적으로 만들고, 논리적 형상을 보존하여 받아들인다. `host_to_tensor_on`은 선택한 Candle 장치에 정규 호스트 텐서를 생성하며, `host_to_tensor`는 CPU 편의 API로 유지된다.

`DenseQOnlyAquaExecutor`는 밀집 F16, BF16, F32, F64 matmul을 가로챈다. 두 Candle 요청 레이아웃을 정확한 논리 순서로 구체화하고, F32로 정규화하며, 외부에서 생성된 실행 계획을 사용하여 왼쪽 활성화에 ExSIA를 실행하고, 손실이 있는 Q 전용 `q * 2^theta` 재구성을 수행한 뒤, 최종 곱셈을 Candle의 CPU matmul에 위임한다. 일치하지 않거나 지원되지 않는 dtype과 가로채지 않은 연산은 CPU-shadow 폴백을 사용한다.

`FixedStripePlanner`는 통합 및 테스트를 위한 결정론적 브리지 정책이다. 의도적으로 `aqua-candle`에 위치하며, 런타임 타일러, 하드웨어 용량 모델, 스크래치패드 플래너 또는 정규 ExSIA 구성의 일부가 아니다.

`AquaTileSelector`는 별도의 호스트/런타임 하드웨어 정책이다. 독립적인 활성화, 가중치, HP1 메타데이터, 누산기, 전체 논리 K ExSIA 슬롯 용량을 검사하면서 Gemmini의 J-이후-I-이후-K 인수 증가 순서를 보존한다. 선택된 스트라이프 행은 ExSIA 실행 전에 검증된 `ActivationExecutionPlan`에 고정된다.

`make -C hw/bsv verify`는 positive Bluesim, expected-failure, assertions-disabled
safety test와 대표 BSC Verilog 생성을 검증한다. 이는 물리 FPGA synthesis
검증이 아니다. BRAM inference, LUT/DSP 사용량, timing/Fmax와 post-synthesis
area는 아직 측정하지 않았다.

## ExSIA 경계

정규 ExSIA 입력은 외부에서 제공된 `ActivationExecutionPlan`과 쌍을 이루는 검증된 연속 F32 `HostTensor`이다. 스트라이프 경계는 실행 컨텍스트이고, 목표 정밀도는 ExSIA 구성이며, `AQUA_BLOCK_SIZE = 32`는 ExSIA, RaCo, 향후 정수 가중치 스케일 그룹이 공유하는 불변 K 좌표 계약이다. 스트라이프 그룹화를 변경하면 스트라이프 지수가 달라질 수 있으며, 따라서 실행 의미 체계도 달라질 수 있다.

ExSIA는 클리핑된 양자화 값, 스트라이프별 theta 값, 스트라이프 범위 잔차 이벤트를 방출한다. 잔차 좌표는 스트라이프 로컬 행과 원래 논리 K를 사용한다. 현재 Candle 브리지는 클리핑된 값과 theta만 소비한다. Rust RaCo 참조 구현은 잔차를 별도로 소비하며 활성화 theta 또는 가중치 스케일을 적용하지 않고 원시 `잔차 정수 × 정수 가중치 코드` 보정을 계산한다.

Rust 참조 구현은 향후 BSV 구현을 위한 의미 체계 계약이다. AQuA는 하드웨어 지향 동작을 명시적으로 만들기 위해 비정규 활성화 값을 의도적으로 0으로 플러시한다.

## 현재 범위 및 연기된 작업

이 마일스톤은 모델 품질/에뮬레이션 배관을 제공하며, 가속기 상주 또는 가속을 제공하지 않는다. 구체적으로 다음과 같다.

* `Device::Aqua`는 CPU-shadow `Storage::Aqua`를 사용한다.
* 양자화된 Candle 가중치는 기존 CPU/CUDA/Metal `QStorage`에 남아 있으며, `QStorage::Aqua`는 없다.
* 밀집 Q 전용 재구성은 손실이 있으며 잔차를 추가하지 않는다.
* RaCo 균형형 기수, 논리 스트라이프 작업, 정수 가중치 코드 실행, 기수 합성, 직접적인 정확 동등성 테스트가 구현되어 있다.
* Q8_HP1 GGUF 프로파일 감지, 로드 가로채기, 정규 가중치 추출, 직접적인 블록 LEFT-shift 통계와 행 RIGHT-shift 통계가 구현되어 있다.
* 리소스를 고려하는 Rust 매크로 타일 선택과 활성화 계획 생성이 구현되어 있다. BSV 스케줄러는 스트라이프를 부분적인 DIM 경계 배열 작업으로 확장하고, K를 정규 너비 32 블록 경계 조각으로 분할한다.
* BSV 메모리 기반은 타입이 지정된 로컬 주소, 별도의 뱅크형 활성화 및 가중치 스크래치패드, HP1 메타데이터, 광폭 누산, 응답 백프레셔가 적용된 읽기 및 쓰기를 구현한다.
* 태그가 지정된 BSV 로드/스토어 스테이징은 활성화, 정규 `[J][K]` 가중치 코드, J 열별 HP1 블록/행 메타데이터, 원시 누산기 출력, 요청 소비 후 최소 한 사이클 뒤의 공급자 응답, 확인 응답으로 제어되는 완료를 포괄한다.
* 완전한 Candle RaCo 실행기, ExSIF 스케일 통합, 물리 패킷 형식 또는 가속기 상주 RaCo 스토리지는 없다.
* 직접적인 HP1 block LEFT-shift 및 row RIGHT-shift 메타데이터 저장은 구현되어 있지만, 해당 정수 시프트 산술 유닛, 물리 공급자 어댑터, 가중치 이미지 또는 RaCo/가중치 스케일 병합은 없다.
* WS 시스톨릭 배열과 PE 프리로드/재정렬은 연기되었으며, 이 기반에는 행렬 데이터패스 통합이 없다.
* BSV ExSIA 및 BSV RaCo 실행은 비트 단위 정확한 데이터패스 단계로 연기되어 있다.
* `AquaLoopMatmul`의 매크로 K 순회, 두 컨텍스트 로드/실행 중첩, 슬롯 할당과 물리 DMA는 연기되어 있다. 아직 구현되지 않은 슬롯 또는 매크로 K 상태는 현재 BSV 계약에 포함하지 않는다. 공급자 인터페이스는 논리적 시뮬레이션 경계이며, 상호 연결 구현이 아니다.
* 중간 텐서는 가속기에 상주하지 않는다.
* ExSIF, KV-cache 오프로딩, UART, PCIe 또는 FPGA 보드 지원은 없다.

RaCo는 Q 전용 역양자화와 분리되어 있다. Rust 코어는 원시 정수 보정에서 멈추며, 부동소수점 스케일 통합과 Candle 결과 덧셈은 향후 계층이다.

## Candle 포크

Candle은 `third_party/candle`에 있는 Git 서브모듈이며, `.gitmodules`에 선언된 AQuA 통합 포크와 브랜치를 추적한다.

```text
https://github.com/code0-god/candle-AQuA.git
aqua/integration
```

Candle 측 실행기 트레이트에는 AQuA 저장소 타입이 포함되지 않아 의존성 방향을 보존한다. Candle은 주입 경계를 정의하고 `aqua-candle`이 이를 구현한다. 관련이 없는 `aqua-runtime::AquaExecutor` 호스트 트레이트는 수정되지 않으며 `candle_core::AquaExecutor`와 혼합되지 않는다.

새로 클론한 후:

```bash
git submodule update --init --recursive
```

## 개발

```bash
cargo fmt --check
cargo check --workspace
cargo test --workspace
cargo test -p aqua-runtime
cargo test -p aqua-candle --test round_trip
cargo test -p aqua-candle --test aqua_device
cargo clippy --workspace --all-targets -- -D warnings
cargo run -p aqua-host
cargo run -p aqua-host --release -- inspect-hp1 <model.gguf>
make -C hw/bsv verify
```

## 로드맵

1. 정규 `[J][K]` 공급자 의미를 변경하지 않고 가중치 고정형 시스톨릭 배열과 PE 프리로드 재정렬을 이식하고 검증한다.
2. HP1 block LEFT-shift 및 row RIGHT-shift 정수 실행 유닛을 추가한다.
3. BSV ExSIA 및 RaCo 데이터패스를 구현하고 비트 단위로 정확하게 검증한다.
4. `AquaLoopMatmul`의 두 컨텍스트 로드/실행/스토어 중첩을 추가한다.
5. 태그가 지정된 공급자 경계 아래에 물리 DMA 어댑터를 연결한다.
6. RaCo/ExSIF 스케일링, 비선형 트랜스포머 연산, 가속기 상주 텐서를 통합한다.
