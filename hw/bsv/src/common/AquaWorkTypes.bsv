package AquaWorkTypes;

import AquaLocalAddr::*;
import AquaTypes::*;

// 전체 matrix를 즉시 처리할지, ExSIA stripe가 준비될 때마다 처리할지 선택.
typedef enum {
    FullMatrix,
    AsyncStripes
} MatmulMode deriving (Bits, Eq, FShow);



// 하나의 전체 matmul 작업과 host-selected execution geometry.
typedef struct {
    MatmulJobId jobId;
    MatmulMode mode;

    MatrixExtent m;
    MatrixExtent n;
    MatrixExtent k;

    MatrixExtent stripeRows;
    MatrixExtent macroNTileColumns;

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

    AquaLocalAddr activationBase;

    UInt#(64) stripeContext;
} ActivationStripe deriving (Bits, Eq, FShow);


// 한 번의 physical systolic-array 실행에서 처리할 M/J 범위.
typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;

    MatrixExtent iStart;
    MatrixExtent jStart;

    ArrayCount iCount;
    ArrayCount jCount;

    MatrixExtent kTileStart;
    MatrixExtent kTileCount;

} ArrayWork#(numeric type arrayDim) deriving (Bits, Eq, FShow);


// ArrayWork의 K 범위를 실제 실행 가능한 fragment로 분할한 단위.
typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;

    MatrixExtent fragmentKStart;
    ArrayCount fragmentKCount;
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
// ArrayWork는 physical systolic array가 한 번에 처리할 M/J 범위이며
// iCount와 jCount는 arrayDim 이하여야 한다.
//
// KFragment는 ArrayWork의 K 범위를 arrayDim 및 AQuA block size 32에
// 맞게 다시 나눈 실제 reduction 실행 단위다.
//
// accumulate=False는 해당 output accumulator에 대한 첫 contribution,
// accumulate=True는 기존 accumulator 값에 계속 더해야 함을 의미한다.

endpackage
