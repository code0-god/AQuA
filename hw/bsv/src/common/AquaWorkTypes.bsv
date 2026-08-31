package AquaWorkTypes;

import AquaLocalAddr::*;
import AquaTypes::*;

// 전체 matrix를 즉시 처리할지, ExSIA stripe가 준비될 때마다 처리할지 선택.
typedef enum {
    FullMatrix,
    AsyncStripes
} MatmulMode deriving (Bits, Eq, FShow);


// 현재 기본 local-memory 주소 형식.
typedef AquaLocalAddr#(2, 8, 16) DefaultAquaLocalAddr;

// 0부터 arrayDim까지 표현할 수 있는 array-local element count.
typedef UInt#(TLog#(TAdd#(arrayDim, 1)))
    ArrayExtent#(numeric type arrayDim);


// 하나의 전체 matmul 작업과 host-selected execution geometry.
typedef struct {
    MatmulJobId jobId;
    MatmulMode mode;

    MatrixExtent m;
    MatrixExtent n;
    MatrixExtent k;

    MatrixExtent stripeRows;
    MatrixExtent macroNTileColumns;
    MatrixExtent macroKTileElements;

    HostTensorId activationTensor;
    HostTensorId weightTensor;
    HostTensorId outputTensor;

    UInt#(64) jobContext;
} AquaMatmulDescriptor deriving (Bits, Eq, FShow);


// 실행 가능한 activation stripe 하나.
typedef struct {
    StripeId stripeId;

    MatrixExtent rowBegin;
    MatrixExtent rowCount;

    DefaultAquaLocalAddr activationBase;

    UInt#(64) stripeContext;
} ActivationStripe deriving (Bits, Eq, FShow);


// 하나의 local-memory resident macro M/N/K tile.
typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;

    MatrixExtent macroMStart;
    MatrixExtent macroNStart;
    MatrixExtent macroKStart;

    MatrixExtent macroMCount;
    MatrixExtent macroNCount;
    MatrixExtent macroKCount;

    LocalSlotId slot;
} MacroTile deriving (Bits, Eq, FShow);


// 한 번의 physical systolic-array 실행에서 처리할 M/J 범위.
typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;

    MatrixExtent iStart;
    MatrixExtent jStart;

    ArrayExtent#(arrayDim) iCount;
    ArrayExtent#(arrayDim) jCount;

    MatrixExtent kTileStart;
    MatrixExtent kTileCount;

    LocalSlotId slot;
} ArrayWork#(numeric type arrayDim) deriving (Bits, Eq, FShow);


// ArrayWork의 K 범위를 실제 실행 가능한 fragment로 분할한 단위.
typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;

    MatrixExtent fragmentKStart;
    MatrixExtent fragmentKCount;
    MatrixExtent fragmentBlockIndex;

    Bool fragmentEndsBlock;
    Bool accumulate;
} KFragment deriving (Bits, Eq, FShow);


// 하나의 stripe가 완전히 처리되었음을 상위 계층에 전달.
typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;

    UInt#(64) completionContext;
} StripeCompletion deriving (Bits, Eq, FShow);


// ============================================================================
// Notes
// ============================================================================
//
// Execution hierarchy:
//
//   AquaMatmulDescriptor
//       ↓
//   ActivationStripe
//       ↓
//   MacroTile
//       ↓
//   ArrayWork
//       ↓
//   KFragment
//
// AquaMatmulDescriptor는 전체 M/N/K와 host-selected tile geometry를
// 전달한다.
//
// ActivationStripe는 ExSIA와 matmul scheduler가 공유하는 M-direction
// execution unit이다.
//
// MacroTile은 scratchpad에 resident할 M/N/K 범위를 표현한다.
// 현재 타입은 정의되어 있지만 전체 MacroTile 순회를 담당하는
// AquaLoopMatmul은 아직 구현되지 않았다.
//
// ArrayWork는 physical systolic array가 한 번에 처리할 M/J 범위이며
// iCount와 jCount는 arrayDim 이하여야 한다.
//
// KFragment는 ArrayWork의 K 범위를 arrayDim 및 AQuA block size 32에
// 맞게 다시 나눈 실제 reduction 실행 단위다.
//
// accumulate=False는 해당 output accumulator에 대한 첫 contribution,
// accumulate=True는 기존 accumulator 값에 계속 더해야 함을 의미한다.

endpackage
