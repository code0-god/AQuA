package AquaMemoryTypes;

import AquaTypes::*;
import AquaWorkTypes::*;
import Vector::*;

typedef enum {
    MemoryActivation,
    MemoryWeightCode,
    MemoryHp1BlockShift,
    MemoryHp1RowScale,
    MemoryRawOutput
} AquaMemoryKind deriving (Bits, Eq, FShow);

typedef struct {
    MatrixExtent start;
    MatrixExtent count;
} LogicalRange deriving (Bits, Eq, FShow);

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    MacroTileId macroTileId;
    ArrayWorkId arrayWorkId;
    KFragmentId fragmentId;
    AquaMemoryKind kind;
    AquaMemoryTxnId transactionId;
    DefaultAquaLocalAddr localDestination;
} AquaMemoryTag deriving (Bits, Eq, FShow);

typedef struct {
    AquaMemoryTag tag;
    HostTensorId tensorId;
    LogicalRange outer;
    LogicalRange inner;
} AquaMemoryReadRequest deriving (Bits, Eq, FShow);

typedef struct {
    AquaMemoryTag tag;
    payload_t payload;
} AquaMemoryReadResponse#(type payload_t)
    deriving (Bits, Eq, FShow);

typedef struct {
    Vector#(lanes, Bool) mask;
    Vector#(lanes, element_t) data;
} ScratchpadRowPayload#(
    numeric type lanes,
    type element_t
) deriving (Bits, Eq, FShow);

typedef AquaMemoryReadResponse#(
    ScratchpadRowPayload#(lanes, Int#(elementWidth))
) ActivationMemoryResponse#(
    numeric type lanes,
    numeric type elementWidth
);

typedef AquaMemoryReadResponse#(
    ScratchpadRowPayload#(lanes, Bit#(elementWidth))
) WeightMemoryResponse#(
    numeric type lanes,
    numeric type elementWidth
);

typedef AquaMemoryReadResponse#(
    Hp1BlockScale#(shiftWidth)
) BlockShiftMemoryResponse#(numeric type shiftWidth);

typedef AquaMemoryReadResponse#(
    UInt#(shiftWidth)
) RowScaleMemoryResponse#(numeric type shiftWidth);

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    MacroTileId macroTileId;
    ArrayWorkId arrayWorkId;
    KFragmentId fragmentId;
    HostTensorId activationTensor;
    HostTensorId weightTensor;
    MatrixExtent iStart;
    ArrayExtent#(arrayDim) iCount;
    MatrixExtent jStart;
    ArrayExtent#(arrayDim) jCount;
    MatrixExtent fragmentKStart;
    MatrixExtent fragmentKCount;
    MatrixExtent fragmentBlockIndex;
    DefaultAquaLocalAddr activationBase;
    DefaultAquaLocalAddr weightBase;
    DefaultAquaLocalAddr blockShiftDestination;
    DefaultAquaLocalAddr rowScaleDestination;
} ProviderLoadWork#(numeric type arrayDim)
    deriving (Bits, Eq, FShow);

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    MacroTileId macroTileId;
    ArrayWorkId arrayWorkId;
    KFragmentId fragmentId;
} LoadCompletion deriving (Bits, Eq, FShow);

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    MacroTileId macroTileId;
    ArrayWorkId arrayWorkId;
    HostTensorId outputTensor;
    MatrixExtent iStart;
    ArrayExtent#(arrayDim) iCount;
    MatrixExtent jStart;
    ArrayExtent#(arrayDim) jCount;
    DefaultAquaLocalAddr accumulatorBase;
} StoreWork#(numeric type arrayDim)
    deriving (Bits, Eq, FShow);

typedef struct {
    AquaMemoryTag tag;
    HostTensorId tensorId;
    LogicalRange outputRow;
    LogicalRange outputColumn;
    Int#(accWidth) rawValue;
} AquaMemoryWriteRequest#(numeric type accWidth)
    deriving (Bits, Eq, FShow);

typedef struct {
    AquaMemoryTag tag;
    Bool accepted;
} AquaMemoryWriteAck deriving (Bits, Eq, FShow);

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    MacroTileId macroTileId;
    ArrayWorkId arrayWorkId;
} StoreCompletion deriving (Bits, Eq, FShow);

endpackage
