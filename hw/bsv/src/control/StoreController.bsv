package StoreController;

import Assert::*;
import AccumulatorMem::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import FIFOF::*;
import SpecialFIFOs::*;

function AquaLocalAddr accumulatorAddress(
    StoreWork#(arrayDim) work,
    MatrixExtent localI,
    MatrixExtent localJ
);
    UInt#(32) baseBank = zeroExtend(unpack(work.accumulatorBase.bank));
    UInt#(32) baseRow = zeroExtend(unpack(work.accumulatorBase.row));
    return AquaLocalAddr {
        region: LocalAccumulator,
        bank: truncate(pack(baseBank + localJ)),
        row: truncate(pack(baseRow + localI))
    };
endfunction

function AquaMemoryTag storeTag(
    StoreWork#(arrayDim) work,
    MatrixExtent transaction,
    AquaLocalAddr source
);
    return AquaMemoryTag {
        jobId: work.jobId,
        stripeId: work.stripeId,
        arrayWorkId: work.arrayWorkId,
        fragmentId: 0,
        transactionId: memoryTransactionId(transaction),
        localAddress: source
    };
endfunction

function AquaMemoryWriteRequest#(accWidth) outputWriteRequest(
    StoreWork#(arrayDim) work,
    MatrixExtent localI,
    MatrixExtent localJ,
    Int#(accWidth) rawValue
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

    interface WritePortIfc#(accWidth) outputPort;

    method Bool completionValid;
    method StoreCompletion completion;
    method Action consumeCompletion;
endinterface

function Bool storeWorkValid(
    StoreWork#(arrayDim) work,
    Integer bankCount,
    Integer rowCount
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

    return
        work.iCount > 0
        && work.jCount > 0
        && work.iCount <= fromInteger(valueOf(arrayDim))
        && work.jCount <= fromInteger(valueOf(arrayDim))
        && logicalIEnd <= fromInteger(2 ** 32 - 1)
        && logicalJEnd <= fromInteger(2 ** 32 - 1)
        && work.accumulatorBase.region == LocalAccumulator
        && localRowEnd <= fromInteger(rowCount)
        && localBankEnd <= fromInteger(bankCount)
        && transactionCount <= fromInteger(2 ** 32);
endfunction

module mkStoreController#(
    AccumulatorMemIfc#(bankCount, rowCount, accWidth) accumulator
)(StoreControllerIfc#(arrayDim, bankCount, rowCount, accWidth))
    provisos (
        Add#(bankAddrPadding, TLog#(TAdd#(bankCount, 1)), 8),
        Add#(rowAddrPadding, TLog#(TAdd#(rowCount, 1)), 16)
    );

    staticAssert(
        valueOf(bankCount) > 0
        && valueOf(bankCount) <= 2 ** 8,
        "accumulator bank count exceeds local address width"
    );
    staticAssert(
        valueOf(rowCount) > 0
        && valueOf(rowCount) <= 2 ** 16,
        "accumulator row count exceeds local address width"
    );

    FIFOF#(AquaMemoryWriteRequest#(accWidth)) outputRequests
        <- mkPipelineFIFOF;
    FIFOF#(StoreCompletion) completions <- mkPipelineFIFOF;
    Reg#(StoreState) state <- mkReg(StoreIdle);
    Reg#(Maybe#(StoreWork#(arrayDim))) active <- mkReg(tagged Invalid);
    Reg#(ArrayCount) localI <- mkReg(0);
    Reg#(ArrayCount) localJ <- mkReg(0);
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
        dynamicAssert(response.bank == truncate(request.tag.localAddress.bank),
                      "accumulator response bank mismatch");
        dynamicAssert(response.row == truncate(request.tag.localAddress.row),
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
        Bool valid = storeWorkValid(
            work,
            valueOf(bankCount),
            valueOf(rowCount)
        );

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

        if (valid) begin
            active <= tagged Valid work;
            localI <= 0;
            localJ <= 0;
            pendingAck <= tagged Invalid;
            state <= StoreRead;
        end
    endmethod

    interface WritePortIfc outputPort;
        interface WriteRequestSourceIfc requests;
            method Bool valid = outputRequests.notEmpty;
            method AquaMemoryWriteRequest#(accWidth) first
                if (outputRequests.notEmpty);
                return outputRequests.first;
            endmethod
            method Action consume
                if (
                    outputRequests.notEmpty
                    && state == StoreOfferWrite
                    && isValid(active)
                );
                pendingAck <= tagged Valid outputRequests.first.tag;
                outputRequests.deq;
                state <= StoreWaitAck;
            endmethod
        endinterface

        interface WriteResponseSinkIfc responses;
            method Bool ready(AquaMemoryWriteAck acknowledgement);
                return
                    state == StoreWaitAck
                    && isValid(active)
                    && isValid(pendingAck)
                    && completions.notFull
                    && acknowledgement.accepted
                    && acknowledgement.tag == fromMaybe(?, pendingAck);
            endmethod

            method Action put(AquaMemoryWriteAck acknowledgement)
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
                dynamicAssert(
                    valid,
                    "output acknowledgement mismatch or rejection"
                );
                if (valid) begin
                    pendingAck <= tagged Invalid;
                    if (
                        localJ + 1 == work.jCount
                        && localI + 1 == work.iCount
                    ) begin
                        completions.enq(StoreCompletion {
                            jobId: work.jobId,
                            stripeId: work.stripeId,
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
        endinterface
    endinterface

    method Bool completionValid = completions.notEmpty;
    method StoreCompletion completion if (completions.notEmpty);
        return completions.first;
    endmethod
    method Action consumeCompletion if (completions.notEmpty);
        completions.deq;
    endmethod
endmodule

endpackage
