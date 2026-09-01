package AquaMemoryProtocol;

import AquaLocalAddr::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import Vector::*;

typedef struct {
    MatrixExtent start;
    MatrixExtent count;
} LogicalRange deriving (Bits, Eq, FShow);

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    ArrayWorkId arrayWorkId;
    KFragmentId fragmentId;
    AquaMemoryTxnId transactionId;
    AquaLocalAddr localAddress;
} AquaMemoryTag deriving (Bits, Eq, FShow);

typedef struct {
    AquaMemoryTag tag;
    HostTensorId tensorId;
    LogicalRange outer;
    LogicalRange inner;
} AquaMemoryReadRequest deriving (Bits, Eq, FShow);

interface ReadRequestSourceIfc;
    method Bool valid;
    method AquaMemoryReadRequest first;
    method Action consume;
endinterface

interface ReadResponseSinkIfc#(type response_t);
    method Bool ready(response_t response);
    method Action put(response_t response);
endinterface

interface ReadPortIfc#(type response_t);
    interface ReadRequestSourceIfc requests;
    interface ReadResponseSinkIfc#(response_t) responses;
endinterface

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

typedef ScratchpadRowPayload#(
    arrayDim,
    Hp1BlockScale#(blockShiftWidth)
) Hp1BlockScaleRow#(
    numeric type arrayDim,
    numeric type blockShiftWidth
);

typedef ScratchpadRowPayload#(
    arrayDim,
    UInt#(rowShiftWidth)
) Hp1RowShiftRow#(
    numeric type arrayDim,
    numeric type rowShiftWidth
);

typedef AquaMemoryReadResponse#(
    Hp1BlockScaleRow#(arrayDim, blockShiftWidth)
) BlockShiftMemoryResponse#(
    numeric type arrayDim,
    numeric type blockShiftWidth
);

typedef AquaMemoryReadResponse#(
    Hp1RowShiftRow#(arrayDim, rowShiftWidth)
) RowScaleMemoryResponse#(
    numeric type arrayDim,
    numeric type rowShiftWidth
);

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    ArrayWorkId arrayWorkId;
    KFragmentId fragmentId;
    HostTensorId activationTensor;
    HostTensorId weightTensor;
    MatrixExtent iStart;
    ArrayCount iCount;
    MatrixExtent jStart;
    ArrayCount jCount;
    MatrixExtent fragmentKStart;
    ArrayCount fragmentKCount;
    MatrixExtent fragmentBlockIndex;
    AquaLocalAddr activationBase;
    AquaLocalAddr weightBase;
    AquaLocalAddr blockShiftDestination;
    AquaLocalAddr rowScaleDestination;
} ProviderLoadWork#(numeric type arrayDim)
    deriving (Bits, Eq, FShow);

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    ArrayWorkId arrayWorkId;
    KFragmentId fragmentId;
} LoadCompletion deriving (Bits, Eq, FShow);

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    ArrayWorkId arrayWorkId;
    HostTensorId outputTensor;
    MatrixExtent iStart;
    ArrayCount iCount;
    MatrixExtent jStart;
    ArrayCount jCount;
    AquaLocalAddr accumulatorBase;
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

interface WriteRequestSourceIfc#(numeric type accWidth);
    method Bool valid;
    method AquaMemoryWriteRequest#(accWidth) first;
    method Action consume;
endinterface

interface WriteResponseSinkIfc;
    method Bool ready(AquaMemoryWriteAck acknowledgement);
    method Action put(AquaMemoryWriteAck acknowledgement);
endinterface

interface WritePortIfc#(numeric type accWidth);
    interface WriteRequestSourceIfc#(accWidth) requests;
    interface WriteResponseSinkIfc responses;
endinterface

function AquaMemoryTxnId memoryTransactionId(MatrixExtent index);
    return zeroExtend(index);
endfunction

typedef struct {
    MatmulJobId jobId;
    StripeId stripeId;
    ArrayWorkId arrayWorkId;
} StoreCompletion deriving (Bits, Eq, FShow);

endpackage
