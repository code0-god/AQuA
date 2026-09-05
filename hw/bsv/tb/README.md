# BSV testbenches

## 실행 판정

positive test는 다음을 모두 만족해야 한다.

1. invocation command가 성공한다.
2. 해당 test 전용 log에 정확한 최종 `PASS: mkTb...` token이 있다.
3. 예상하지 않은 dynamic assertion, assertion, `Error`, `FATAL`, `FAIL`
   diagnostic이 없다.

따라서 exit code만, 또는 다른 top이 남긴 PASS만으로 positive 성공을 판정하지
않는다. `bsv-test-one`과 no-assert 단일 top invocation도 같은 isolated log
정책을 사용한다.

expected-failure는 단순 nonzero가 아니다. runtime failure는 지정한 dynamic
assertion diagnostic을, elaboration failure는 지정한 static/elaboration
diagnostic을 관찰해야 한다. 각 top은 독립 log로 실행한다.

```bash
make -C hw/bsv bsv-test-one TOP=mkTbMatmulScheduler
make -C hw/bsv bsv-test-expected-one TOP=mkTbAccumulatorOverflow
make -C hw/bsv verify-memory-depth
```

## Memory-depth/address-width 범위

검증 목록은 positive 22개, expected-failure 23개(runtime 18개와
elaboration 5개), assertions-disabled 6개, RTL generation 5개, public port
audit 3개다. 새 경계 fixture는 `mkTbMemoryDepth`, `mkTbMemoryAddressWidth`이며,
`mkMemoryMaxDepthSynthTop`은 65536-depth StoreController compile-only fixture다.

RegFile storage는 정확히 `0 .. depth - 1`이어야 하고 depth는 static하게
positive여야 한다. `AquaLocalAddr::MemoryAddrWidth#(depth)`는
`TMax#(1, TLog#(depth))`이며 depth 1/8/17/65536에 1/3/5/16 bit를 요구한다.
65535는 최대 유효 row이고 65536은 더 넓은 controller 산술에서 invalid로
검사한다. 1-bit 최소 폭은 BSC RegFile이 zero-width를 지원할 수 있는 것과
별개의 AQuA 정책이다. max-depth/address-width gate의
`verify-address-width` target을 사용한다.

## RTL wrapper 범위

BSC RTL generation은 물리 FPGA synthesis가 아니다.
`mkSchedulerSynthTop`과 `mkLoopMatmulSynthTop`은 production interface 전체를
공개한다. `mkMemorySubsystemSynthTop`은 runtime load/store, 네 typed provider
port, output port와 accumulator를 공개하며 local scratchpad/HP1 inspection은
의도적으로 공개하지 않는다. BRAM inference, area, timing/Fmax는 이 gate의
증명 범위가 아니다.

향후 작은 testbench는 ExSIA hardware output을 고정 software golden vector와
비교한다.
