package StoreController;

import Assert::*;
import AccumulatorMem::*;
import AquaLocalAddr::*;
import AquaMemoryTypes::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import FIFOF::*;
import SpecialFIFOs::*;
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

typedef enum {
    StoreIdle,
    StoreRead,
    StoreWaitRead,
    StoreOfferWrite,
    StoreWaitAck
} StoreState deriving (Bits, Eq, FShow);

interface StoreControllerIfc#(
    numeric type arrayDim,
    numeric type bankCount,
    numeric type rowCount,
    numeric type accWidth
);
    method Bool startReady;
    method Action start(StoreWork#(arrayDim) work);

    method Bool outputRequestValid;
    method AquaMemoryWriteRequest#(accWidth) outputRequest;
    method Action consumeOutputRequest;
    method Bool outputAckReady(AquaMemoryWriteAck acknowledgement);
    method Action putOutputAck(AquaMemoryWriteAck acknowledgement);

    method Bool completionValid;
    method StoreCompletion completion;
    method Action consumeCompletion;
endinterface

module mkStoreController#(
    AccumulatorMemIfc#(bankCount, rowCount, accWidth) accumulator
)(StoreControllerIfc#(arrayDim, bankCount, rowCount, accWidth))
    provisos (
        Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32),
        Add#(bankAddrPadding, TLog#(TAdd#(bankCount, 1)), 8),
        Add#(rowAddrPadding, TLog#(TAdd#(rowCount, 1)), 16)
    );

    FIFOF#(AquaMemoryWriteRequest#(accWidth)) outputRequests
        <- mkPipelineFIFOF;
    FIFOF#(StoreCompletion) completions <- mkPipelineFIFOF;
    Reg#(StoreState) state <- mkReg(StoreIdle);
    Reg#(Maybe#(StoreWork#(arrayDim))) active <- mkReg(tagged Invalid);
    Reg#(ArrayExtent#(arrayDim)) localI <- mkReg(0);
    Reg#(ArrayExtent#(arrayDim)) localJ <- mkReg(0);
    Reg#(Maybe#(AquaMemoryTag)) pendingAck <- mkReg(tagged Invalid);

    rule issueAccumulatorRead (
        state == StoreRead
        && isValid(active)
        && accumulator.readReady
    );
        let work = fromMaybe(?, active);
        MatrixExtent i = zeroExtend(localI);
        MatrixExtent j = zeroExtend(localJ);
        let address = accumulatorAddress(work, i, j);
        accumulator.requestRead(
            truncate(address.bank),
            truncate(address.row)
        );
        state <= StoreWaitRead;
    endrule

    rule captureAccumulatorRead (
        state == StoreWaitRead
        && isValid(active)
        && accumulator.readValid
        && outputRequests.notFull
    );
        let work = fromMaybe(?, active);
        let response = accumulator.readResponse;
        MatrixExtent i = zeroExtend(localI);
        MatrixExtent j = zeroExtend(localJ);
        let request = outputWriteRequest(work, i, j, response.value);
        dynamicAssert(response.bank == truncate(request.tag.localDestination.bank),
                      "accumulator response bank mismatch");
        dynamicAssert(response.row == truncate(request.tag.localDestination.row),
                      "accumulator response row mismatch");
        outputRequests.enq(request);
        accumulator.consumeRead;
        state <= StoreOfferWrite;
    endrule

    method Bool startReady =
        state == StoreIdle
        && !isValid(active)
        && !completions.notEmpty;

    method Action start(StoreWork#(arrayDim) work)
        if (
            state == StoreIdle
            && !isValid(active)
            && !completions.notEmpty
        );
        UInt#(32) iCount = zeroExtend(work.iCount);
        UInt#(32) jCount = zeroExtend(work.jCount);
        UInt#(33) logicalIEnd =
            zeroExtend(work.iStart) + zeroExtend(iCount);
        UInt#(33) logicalJEnd =
            zeroExtend(work.jStart) + zeroExtend(jCount);
        UInt#(32) baseRow =
            zeroExtend(unpack(work.accumulatorBase.row));
        UInt#(32) baseBank =
            zeroExtend(unpack(work.accumulatorBase.bank));
        UInt#(33) localRowEnd = zeroExtend(baseRow) + zeroExtend(iCount);
        UInt#(33) localBankEnd = zeroExtend(baseBank) + zeroExtend(jCount);
        UInt#(64) transactionCount =
            zeroExtend(iCount) * zeroExtend(jCount);

        dynamicAssert(work.iCount > 0, "store I count must be positive");
        dynamicAssert(work.jCount > 0, "store J count must be positive");
        dynamicAssert(work.iCount <= fromInteger(valueOf(arrayDim)),
                      "store I count exceeds array dimension");
        dynamicAssert(work.jCount <= fromInteger(valueOf(arrayDim)),
                      "store J count exceeds array dimension");
        dynamicAssert(logicalIEnd <= fromInteger(2 ** 32 - 1),
                      "store output row range overflow");
        dynamicAssert(logicalJEnd <= fromInteger(2 ** 32 - 1),
                      "store output column range overflow");
        dynamicAssert(work.accumulatorBase.region == LocalAccumulator,
                      "store source has wrong local region");
        dynamicAssert(localRowEnd <= fromInteger(valueOf(rowCount)),
                      "store accumulator row range out of bounds");
        dynamicAssert(localBankEnd <= fromInteger(valueOf(bankCount)),
                      "store accumulator bank range out of bounds");
        dynamicAssert(transactionCount <= fromInteger(2 ** 32),
                      "store transaction count exceeds tag range");

        active <= tagged Valid work;
        localI <= 0;
        localJ <= 0;
        pendingAck <= tagged Invalid;
        state <= StoreRead;
    endmethod

    method Bool outputRequestValid = outputRequests.notEmpty;

    method AquaMemoryWriteRequest#(accWidth) outputRequest
        if (outputRequests.notEmpty);
        return outputRequests.first;
    endmethod

    method Action consumeOutputRequest
        if (
            outputRequests.notEmpty
            && state == StoreOfferWrite
            && isValid(active)
        );
        pendingAck <= tagged Valid outputRequests.first.tag;
        outputRequests.deq;
        state <= StoreWaitAck;
    endmethod

    method Bool outputAckReady(AquaMemoryWriteAck acknowledgement);
        return
            state == StoreWaitAck
            && isValid(active)
            && isValid(pendingAck)
            && completions.notFull
            && acknowledgement.accepted
            && acknowledgement.tag == fromMaybe(?, pendingAck);
    endmethod

    method Action putOutputAck(AquaMemoryWriteAck acknowledgement)
        if (
            state == StoreWaitAck
            && isValid(active)
            && isValid(pendingAck)
            && completions.notFull
        );
        let work = fromMaybe(?, active);
        Bool valid =
            acknowledgement.accepted
            && acknowledgement.tag == fromMaybe(?, pendingAck);
        dynamicAssert(valid, "output acknowledgement mismatch or rejection");
        if (valid) begin
            pendingAck <= tagged Invalid;
            if (
                localJ + 1 == work.jCount
                && localI + 1 == work.iCount
            ) begin
                completions.enq(StoreCompletion {
                    jobId: work.jobId,
                    stripeId: work.stripeId,
                    macroTileId: work.macroTileId,
                    arrayWorkId: work.arrayWorkId
                });
                active <= tagged Invalid;
                state <= StoreIdle;
            end
            else if (localJ + 1 == work.jCount) begin
                localJ <= 0;
                localI <= localI + 1;
                state <= StoreRead;
            end
            else begin
                localJ <= localJ + 1;
                state <= StoreRead;
            end
        end
    endmethod

    method Bool completionValid = completions.notEmpty;
    method StoreCompletion completion if (completions.notEmpty);
        return completions.first;
    endmethod
    method Action consumeCompletion if (completions.notEmpty);
        completions.deq;
    endmethod
endmodule

endpackage
