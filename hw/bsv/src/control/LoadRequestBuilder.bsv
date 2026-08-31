package LoadRequestBuilder;

import AquaLocalAddr::*;
import AquaMemoryTypes::*;
import AquaTypes::*;
import AquaWorkTypes::*;

typedef struct {
    MatmulJobId jobId;
    MacroTileId macroTileId;
    HostTensorId weightTensor;
    MatrixExtent jStart;
    MatrixExtent jCount;
    DefaultAquaLocalAddr destination;
} RowScaleReuseKey deriving (Bits, Eq, FShow);

typedef struct {
    RowScaleReuseKey rowKey;
    MatrixExtent blockIndex;
    DefaultAquaLocalAddr destination;
} BlockScaleReuseKey deriving (Bits, Eq, FShow);

function RowScaleReuseKey rowScaleReuseKey(
    ProviderLoadWork#(arrayDim) work
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32)
);
    return RowScaleReuseKey {
        jobId: work.jobId,
        macroTileId: work.macroTileId,
        weightTensor: work.weightTensor,
        jStart: work.jStart,
        jCount: zeroExtend(work.jCount),
        destination: work.rowScaleDestination
    };
endfunction

function BlockScaleReuseKey blockScaleReuseKey(
    ProviderLoadWork#(arrayDim) work
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32)
);
    return BlockScaleReuseKey {
        rowKey: rowScaleReuseKey(work),
        blockIndex: work.fragmentBlockIndex,
        destination: work.blockShiftDestination
    };
endfunction

function AquaMemoryTxnId transactionId(
    AquaMemoryKind kind,
    MatrixExtent index
);
    return
        (zeroExtend(unpack(pack(kind))) << 32)
        | zeroExtend(index);
endfunction

function Bit#(TLog#(arrayDim)) responseLane(
    ProviderLoadWork#(arrayDim) work,
    AquaMemoryTag tag
) provisos (
    Add#(lanePadding, TLog#(arrayDim), 40)
);
    return truncate(pack(tag.transactionId));
endfunction

function AquaMemoryTag loadTag(
    ProviderLoadWork#(arrayDim) work,
    AquaMemoryKind kind,
    MatrixExtent index,
    DefaultAquaLocalAddr destination
);
    return AquaMemoryTag {
        jobId: work.jobId,
        stripeId: work.stripeId,
        macroTileId: work.macroTileId,
        arrayWorkId: work.arrayWorkId,
        fragmentId: work.fragmentId,
        kind: kind,
        transactionId: transactionId(kind, index),
        localDestination: destination
    };
endfunction

function AquaMemoryReadRequest activationRequest(
    ProviderLoadWork#(arrayDim) work,
    MatrixExtent rowIndex,
    Integer bankCount
);
    let destination = offsetBankedAddress(
        work.activationBase,
        rowIndex,
        bankCount
    );
    return AquaMemoryReadRequest {
        tag: loadTag(work, MemoryActivation, rowIndex, destination),
        tensorId: work.activationTensor,
        outer: LogicalRange {
            start: work.iStart + rowIndex,
            count: 1
        },
        inner: LogicalRange {
            start: work.fragmentKStart,
            count: work.fragmentKCount
        }
    };
endfunction

function AquaMemoryReadRequest weightRequest(
    ProviderLoadWork#(arrayDim) work,
    MatrixExtent jIndex,
    Integer bankCount
);
    let destination = offsetBankedAddress(
        work.weightBase,
        jIndex,
        bankCount
    );
    return AquaMemoryReadRequest {
        tag: loadTag(work, MemoryWeightCode, jIndex, destination),
        tensorId: work.weightTensor,
        // Provider orientation remains canonical W_source[J, K].
        outer: LogicalRange {
            start: work.jStart + jIndex,
            count: 1
        },
        inner: LogicalRange {
            start: work.fragmentKStart,
            count: work.fragmentKCount
        }
    };
endfunction

function AquaMemoryReadRequest blockShiftRequest(
    ProviderLoadWork#(arrayDim) work
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32)
);
    return AquaMemoryReadRequest {
        tag: loadTag(
            work,
            MemoryHp1BlockShift,
            0,
            work.blockShiftDestination
        ),
        tensorId: work.weightTensor,
        outer: LogicalRange {
            start: work.jStart,
            count: zeroExtend(work.jCount)
        },
        inner: LogicalRange {
            start: work.fragmentBlockIndex,
            count: 1
        }
    };
endfunction

function AquaMemoryReadRequest rowScaleRequest(
    ProviderLoadWork#(arrayDim) work
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32)
);
    return AquaMemoryReadRequest {
        tag: loadTag(
            work,
            MemoryHp1RowScale,
            0,
            work.rowScaleDestination
        ),
        tensorId: work.weightTensor,
        outer: LogicalRange {
            start: work.jStart,
            count: zeroExtend(work.jCount)
        },
        inner: LogicalRange { start: 0, count: 1 }
    };
endfunction

function Bool matchesActivationResponse(
    ProviderLoadWork#(arrayDim) work,
    AquaMemoryTag tag,
    Integer bankCount
) provisos (
    Add#(lanePadding, TLog#(arrayDim), 32),
    Add#(laneTagPadding, TLog#(arrayDim), 40)
);
    let lane = responseLane(work, tag);
    MatrixExtent index = zeroExtend(unpack(lane));
    return tag == activationRequest(work, index, bankCount).tag;
endfunction

function Bool matchesWeightResponse(
    ProviderLoadWork#(arrayDim) work,
    AquaMemoryTag tag,
    Integer bankCount
) provisos (
    Add#(lanePadding, TLog#(arrayDim), 32),
    Add#(laneTagPadding, TLog#(arrayDim), 40)
);
    let lane = responseLane(work, tag);
    MatrixExtent index = zeroExtend(unpack(lane));
    return tag == weightRequest(work, index, bankCount).tag;
endfunction

function Bool matchesBlockShiftResponse(
    ProviderLoadWork#(arrayDim) work,
    AquaMemoryTag tag
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32)
);
    return tag == blockShiftRequest(work).tag;
endfunction

function Bool matchesRowScaleResponse(
    ProviderLoadWork#(arrayDim) work,
    AquaMemoryTag tag
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32)
);
    return tag == rowScaleRequest(work).tag;
endfunction

endpackage
