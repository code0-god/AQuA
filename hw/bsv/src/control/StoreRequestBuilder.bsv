package StoreRequestBuilder;

import AquaLocalAddr::*;
import AquaMemoryTypes::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import LoadRequestBuilder::*;

function DefaultAquaLocalAddr accumulatorAddress(
    StoreWork#(arrayDim) work,
    MatrixExtent localI,
    MatrixExtent localJ
);
    UInt#(32) baseBank = zeroExtend(unpack(work.accumulatorBase.bank));
    UInt#(32) baseRow = zeroExtend(unpack(work.accumulatorBase.row));
    return DefaultAquaLocalAddr {
        region: LocalAccumulator,
        slot: work.accumulatorBase.slot,
        bank: truncate(pack(baseBank + localJ)),
        row: truncate(pack(baseRow + localI))
    };
endfunction

function AquaMemoryTag storeTag(
    StoreWork#(arrayDim) work,
    MatrixExtent transaction,
    DefaultAquaLocalAddr source
);
    return AquaMemoryTag {
        jobId: work.jobId,
        stripeId: work.stripeId,
        macroTileId: work.macroTileId,
        arrayWorkId: work.arrayWorkId,
        fragmentId: 0,
        kind: MemoryRawOutput,
        transactionId: transactionId(MemoryRawOutput, transaction),
        localDestination: source
    };
endfunction

function AquaMemoryWriteRequest#(accWidth) outputWriteRequest(
    StoreWork#(arrayDim) work,
    MatrixExtent localI,
    MatrixExtent localJ,
    Int#(accWidth) rawValue
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32)
);
    MatrixExtent jCount = zeroExtend(work.jCount);
    UInt#(64) transactionWide =
        zeroExtend(localI) * zeroExtend(jCount)
        + zeroExtend(localJ);
    MatrixExtent transaction = truncate(transactionWide);
    let source = accumulatorAddress(work, localI, localJ);
    return AquaMemoryWriteRequest {
        tag: storeTag(work, transaction, source),
        tensorId: work.outputTensor,
        outputRow: LogicalRange {
            start: work.iStart + localI,
            count: 1
        },
        outputColumn: LogicalRange {
            start: work.jStart + localJ,
            count: 1
        },
        rawValue: rawValue
    };
endfunction

endpackage
