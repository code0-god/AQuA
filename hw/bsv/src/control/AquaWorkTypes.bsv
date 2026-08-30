package AquaWorkTypes;

import AquaLocalAddr::*;
import AquaTypes::*;

typedef enum {
    FullMatrix,
    AsyncStripes
} MatmulMode deriving (Bits, Eq, FShow);

typedef AquaLocalAddr#(2, 8, 16) DefaultAquaLocalAddr;
typedef UInt#(TLog#(TAdd#(arrayDim, 1))) ArrayExtent#(numeric type arrayDim);

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

typedef struct {
    StripeId stripeId;
    MatrixExtent rowBegin;
    MatrixExtent rowCount;
    DefaultAquaLocalAddr activationBase;
    UInt#(64) stripeContext;
} ActivationStripe deriving (Bits, Eq, FShow);

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

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    MatrixExtent fragmentKStart;
    MatrixExtent fragmentKCount;
    MatrixExtent fragmentBlockIndex;
    Bool fragmentEndsBlock;
    Bool accumulate;
} KFragment deriving (Bits, Eq, FShow);

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    UInt#(64) completionContext;
} StripeCompletion deriving (Bits, Eq, FShow);

endpackage
