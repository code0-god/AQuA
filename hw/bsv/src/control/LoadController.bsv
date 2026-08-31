package LoadController;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import FIFOF::*;
import SpecialFIFOs::*;
import Vector::*;

typedef struct {
    MatmulJobId jobId;
    HostTensorId weightTensor;
    MatrixExtent jStart;
    MatrixExtent jCount;
    AquaLocalAddr destination;
} RowScaleReuseKey deriving (Bits, Eq, FShow);

typedef struct {
    RowScaleReuseKey rowKey;
    MatrixExtent blockIndex;
    AquaLocalAddr destination;
} BlockScaleReuseKey deriving (Bits, Eq, FShow);

function RowScaleReuseKey rowScaleReuseKey(
    ProviderLoadWork#(arrayDim) work
);
    return RowScaleReuseKey {
        jobId: work.jobId,
        weightTensor: work.weightTensor,
        jStart: work.jStart,
        jCount: zeroExtend(work.jCount),
        destination: work.rowScaleDestination
    };
endfunction

function BlockScaleReuseKey blockScaleReuseKey(
    ProviderLoadWork#(arrayDim) work
);
    return BlockScaleReuseKey {
        rowKey: rowScaleReuseKey(work),
        blockIndex: work.fragmentBlockIndex,
        destination: work.blockShiftDestination
    };
endfunction

function AquaMemoryTag loadTag(
    ProviderLoadWork#(arrayDim) work,
    MatrixExtent index,
    AquaLocalAddr address
);
    return AquaMemoryTag {
        jobId: work.jobId,
        stripeId: work.stripeId,
        arrayWorkId: work.arrayWorkId,
        fragmentId: work.fragmentId,
        transactionId: memoryTransactionId(index),
        localAddress: address
    };
endfunction

function AquaMemoryReadRequest activationRequest(
    ProviderLoadWork#(arrayDim) work,
    MatrixExtent rowIndex,
    Integer bankCount
);
    let address = offsetBankedAddress(
        work.activationBase,
        rowIndex,
        bankCount
    );
    return AquaMemoryReadRequest {
        tag: loadTag(work, rowIndex, address),
        tensorId: work.activationTensor,
        outer: LogicalRange { start: work.iStart + rowIndex, count: 1 },
        inner: LogicalRange {
            start: work.fragmentKStart,
            count: zeroExtend(work.fragmentKCount)
        }
    };
endfunction

function AquaMemoryReadRequest weightRequest(
    ProviderLoadWork#(arrayDim) work,
    MatrixExtent jIndex,
    Integer bankCount
);
    let address = offsetBankedAddress(
        work.weightBase,
        jIndex,
        bankCount
    );
    return AquaMemoryReadRequest {
        tag: loadTag(work, jIndex, address),
        tensorId: work.weightTensor,
        // Provider orientation remains canonical W_source[J, K].
        outer: LogicalRange { start: work.jStart + jIndex, count: 1 },
        inner: LogicalRange {
            start: work.fragmentKStart,
            count: zeroExtend(work.fragmentKCount)
        }
    };
endfunction

function AquaMemoryReadRequest blockShiftRequest(
    ProviderLoadWork#(arrayDim) work
);
    return AquaMemoryReadRequest {
        tag: loadTag(work, 0, work.blockShiftDestination),
        tensorId: work.weightTensor,
        outer: LogicalRange {
            start: work.jStart,
            count: zeroExtend(work.jCount)
        },
        inner: LogicalRange { start: work.fragmentBlockIndex, count: 1 }
    };
endfunction

function AquaMemoryReadRequest rowShiftRequest(
    ProviderLoadWork#(arrayDim) work
);
    return AquaMemoryReadRequest {
        tag: loadTag(work, 0, work.rowScaleDestination),
        tensorId: work.weightTensor,
        outer: LogicalRange {
            start: work.jStart,
            count: zeroExtend(work.jCount)
        },
        inner: LogicalRange { start: 0, count: 1 }
    };
endfunction

function Bool metadataMaskMatches(
    Vector#(arrayDim, Bool) mask,
    ArrayCount jCount
);
    Bool valid = True;
    for (Integer lane = 0; lane < valueOf(arrayDim); lane = lane + 1) begin
        valid = valid && mask[lane] == (fromInteger(lane) < jCount);
    end
    return valid;
endfunction

interface LoadControllerIfc#(
    numeric type arrayDim,
    numeric type activationBankCount,
    numeric type weightBankCount,
    numeric type metaEntries
);
    method Bool scheduleReady;
    method Action schedule(ProviderLoadWork#(arrayDim) work);

    interface ReadPortIfc#(AquaMemoryTag) activationPort;
    interface ReadPortIfc#(AquaMemoryTag) weightPort;
    interface ReadPortIfc#(AquaMemoryTag) blockShiftPort;
    interface ReadPortIfc#(AquaMemoryTag) rowShiftPort;

    method Bool metadataResponseMaskValid(Vector#(arrayDim, Bool) mask);

    method Bool completionValid;
    method LoadCompletion completion;
    method Action consumeCompletion;
    method UInt#(64) outstandingCycles;
endinterface

function Action validateProviderLoadWork(
    ProviderLoadWork#(arrayDim) work,
    Integer activationBankCount,
    Integer weightBankCount,
    Integer metaEntries
);
    action
        UInt#(32) iCount = zeroExtend(work.iCount);
        UInt#(32) jCount = zeroExtend(work.jCount);
        UInt#(33) iEnd = zeroExtend(work.iStart) + zeroExtend(iCount);
        UInt#(33) jEnd = zeroExtend(work.jStart) + zeroExtend(jCount);
        UInt#(33) kEnd =
            zeroExtend(work.fragmentKStart)
            + zeroExtend(work.fragmentKCount);
        UInt#(32) activationBaseBank =
            zeroExtend(unpack(work.activationBase.bank));
        UInt#(32) activationBaseRow =
            zeroExtend(unpack(work.activationBase.row));
        UInt#(32) weightBaseBank =
            zeroExtend(unpack(work.weightBase.bank));
        UInt#(32) weightBaseRow =
            zeroExtend(unpack(work.weightBase.row));
        UInt#(40) activationLinearEnd =
            zeroExtend(activationBaseRow) * fromInteger(activationBankCount)
            + zeroExtend(activationBaseBank)
            + zeroExtend(iCount == 0 ? 0 : iCount - 1);
        UInt#(40) weightLinearEnd =
            zeroExtend(weightBaseRow) * fromInteger(weightBankCount)
            + zeroExtend(weightBaseBank)
            + zeroExtend(jCount == 0 ? 0 : jCount - 1);
        UInt#(32) blockMetadataBank =
            zeroExtend(unpack(work.blockShiftDestination.bank));
        UInt#(32) blockMetadataRow =
            zeroExtend(unpack(work.blockShiftDestination.row));
        UInt#(32) rowMetadataBank =
            zeroExtend(unpack(work.rowScaleDestination.bank));
        UInt#(32) rowMetadataRow =
            zeroExtend(unpack(work.rowScaleDestination.row));

        dynamicAssert(work.iCount > 0, "load work I count must be positive");
        dynamicAssert(work.jCount > 0, "load work J count must be positive");
        dynamicAssert(work.fragmentKCount > 0,
                      "load fragment K count must be positive");
        dynamicAssert(work.iCount <= fromInteger(valueOf(arrayDim)),
                      "load work I count exceeds array dimension");
        dynamicAssert(work.jCount <= fromInteger(valueOf(arrayDim)),
                      "load work J count exceeds array dimension");
        dynamicAssert(work.fragmentKCount <= fromInteger(valueOf(arrayDim)),
                      "load fragment K count exceeds array dimension");
        dynamicAssert(iEnd <= fromInteger(2 ** 32 - 1),
                      "load work I range overflow");
        dynamicAssert(jEnd <= fromInteger(2 ** 32 - 1),
                      "load work J range overflow");
        dynamicAssert(kEnd <= fromInteger(2 ** 32 - 1),
                      "load work K range overflow");
        dynamicAssert(work.activationBase.region == LocalActivation,
                      "activation base has wrong local region");
        dynamicAssert(work.weightBase.region == LocalWeight,
                      "weight base has wrong local region");
        dynamicAssert(activationBaseBank < fromInteger(activationBankCount),
                      "activation base bank exceeds configured banks");
        dynamicAssert(weightBaseBank < fromInteger(weightBankCount),
                      "weight base bank exceeds configured banks");
        dynamicAssert(
            activationLinearEnd / fromInteger(activationBankCount)
                < fromInteger(2 ** 16),
            "activation local row range overflow"
        );
        dynamicAssert(
            weightLinearEnd / fromInteger(weightBankCount)
                < fromInteger(2 ** 16),
            "weight local row range overflow"
        );
        dynamicAssert(work.blockShiftDestination.region == LocalHp1Meta,
                      "block shift has wrong local region");
        dynamicAssert(work.rowScaleDestination.region == LocalHp1Meta,
                      "row shift has wrong local region");
        dynamicAssert(blockMetadataBank == 0,
                      "block shift metadata bank must be zero");
        dynamicAssert(rowMetadataBank == 0,
                      "row shift metadata bank must be zero");
        dynamicAssert(blockMetadataRow < fromInteger(metaEntries),
                      "block shift metadata row out of bounds");
        dynamicAssert(rowMetadataRow < fromInteger(metaEntries),
                      "row shift metadata row out of bounds");
    endaction
endfunction

module mkLoadController(LoadControllerIfc#(
    arrayDim,
    activationBankCount,
    weightBankCount,
    metaEntries
)) provisos (
    Add#(activationLanePadding, TLog#(arrayDim), 32),
    Add#(weightLanePadding, TLog#(arrayDim), 32)
);
    Reg#(Maybe#(AquaMemoryReadRequest)) activationOffered <- mkReg(tagged Invalid);
    Reg#(Maybe#(AquaMemoryReadRequest)) weightOffered <- mkReg(tagged Invalid);
    Reg#(Maybe#(AquaMemoryReadRequest)) blockOffered <- mkReg(tagged Invalid);
    Reg#(Maybe#(AquaMemoryReadRequest)) rowOffered <- mkReg(tagged Invalid);
    Reg#(Maybe#(AquaMemoryTag)) activationPending <- mkReg(tagged Invalid);
    Reg#(Maybe#(AquaMemoryTag)) weightPending <- mkReg(tagged Invalid);
    Reg#(Maybe#(AquaMemoryTag)) blockPending <- mkReg(tagged Invalid);
    Reg#(Maybe#(AquaMemoryTag)) rowPending <- mkReg(tagged Invalid);
    FIFOF#(LoadCompletion) completions <- mkPipelineFIFOF;
    Reg#(Maybe#(ProviderLoadWork#(arrayDim))) active
        <- mkReg(tagged Invalid);
    Reg#(ArrayCount) activationIssue <- mkReg(0);
    Reg#(ArrayCount) weightIssue <- mkReg(0);
    Reg#(Bool) blockIssued <- mkReg(False);
    Reg#(Bool) rowIssued <- mkReg(False);
    Reg#(Maybe#(RowScaleReuseKey)) lastRowKey <- mkReg(tagged Invalid);
    Reg#(Maybe#(BlockScaleReuseKey)) lastBlockKey <- mkReg(tagged Invalid);
    Reg#(UInt#(64)) stagingCycles <- mkReg(0);

    staticAssert(
        valueOf(arrayDim) == 16
        || valueOf(arrayDim) == 32
        || valueOf(arrayDim) == 64,
        "load controller array dimension must be 16, 32, or 64"
    );

    function Bool rowShiftNeeded(ProviderLoadWork#(arrayDim) work);
        let key = rowScaleReuseKey(work);
        return !isValid(lastRowKey) || fromMaybe(?, lastRowKey) != key;
    endfunction

    function Bool blockShiftNeeded(ProviderLoadWork#(arrayDim) work);
        let key = blockScaleReuseKey(work);
        return !isValid(lastBlockKey) || fromMaybe(?, lastBlockKey) != key;
    endfunction

    rule issueActivation(
        isValid(active)
        && activationIssue < fromMaybe(?, active).iCount
        && !isValid(activationOffered)
        && !isValid(activationPending)
    );
        let work = fromMaybe(?, active);
        MatrixExtent index = zeroExtend(activationIssue);
        activationOffered <= tagged Valid activationRequest(
            work,
            index,
            valueOf(activationBankCount)
        );
        activationIssue <= activationIssue + 1;
    endrule

    rule issueWeight(
        isValid(active)
        && weightIssue < fromMaybe(?, active).jCount
        && !isValid(weightOffered)
        && !isValid(weightPending)
    );
        let work = fromMaybe(?, active);
        MatrixExtent index = zeroExtend(weightIssue);
        weightOffered <= tagged Valid weightRequest(
            work,
            index,
            valueOf(weightBankCount)
        );
        weightIssue <= weightIssue + 1;
    endrule

    rule issueBlockShift(
        isValid(active)
        && !blockIssued
        && !isValid(blockOffered)
        && !isValid(blockPending)
    );
        blockOffered <= tagged Valid blockShiftRequest(fromMaybe(?, active));
        blockIssued <= True;
    endrule

    rule issueRowShift(
        isValid(active)
        && !rowIssued
        && !isValid(rowOffered)
        && !isValid(rowPending)
    );
        rowOffered <= tagged Valid rowShiftRequest(fromMaybe(?, active));
        rowIssued <= True;
    endrule

    rule completeLoad(
        isValid(active)
        && activationIssue == fromMaybe(?, active).iCount
        && weightIssue == fromMaybe(?, active).jCount
        && blockIssued
        && rowIssued
        && !isValid(activationOffered)
        && !isValid(weightOffered)
        && !isValid(blockOffered)
        && !isValid(rowOffered)
        && !isValid(activationPending)
        && !isValid(weightPending)
        && !isValid(blockPending)
        && !isValid(rowPending)
        && completions.notFull
    );
        let work = fromMaybe(?, active);
        completions.enq(LoadCompletion {
            jobId: work.jobId,
            stripeId: work.stripeId,
            arrayWorkId: work.arrayWorkId,
            fragmentId: work.fragmentId
        });
        active <= tagged Invalid;
    endrule

    rule countOutstanding(isValid(active));
        stagingCycles <= stagingCycles + 1;
    endrule

    method Bool scheduleReady = !isValid(active) && completions.notFull;

    method Action schedule(ProviderLoadWork#(arrayDim) work)
        if (!isValid(active) && completions.notFull);
        validateProviderLoadWork(
            work,
            valueOf(activationBankCount),
            valueOf(weightBankCount),
            valueOf(metaEntries)
        );
        active <= tagged Valid work;
        activationIssue <= 0;
        weightIssue <= 0;
        blockIssued <= !blockShiftNeeded(work);
        rowIssued <= !rowShiftNeeded(work);
    endmethod

    interface ReadPortIfc activationPort;
        interface ReadRequestSourceIfc requests;
            method Bool valid = isValid(activationOffered);
            method AquaMemoryReadRequest first if (isValid(activationOffered));
                return fromMaybe(?, activationOffered);
            endmethod
            method Action consume
                if (isValid(activationOffered) && !isValid(activationPending));
                activationPending <= tagged Valid fromMaybe(?, activationOffered).tag;
                activationOffered <= tagged Invalid;
            endmethod
        endinterface
        interface ReadResponseSinkIfc responses;
            method Bool ready(AquaMemoryTag tag) =
                isValid(activationPending)
                && tag == fromMaybe(?, activationPending);
            method Action put(AquaMemoryTag tag);
                Bool valid = isValid(activationPending)
                    && tag == fromMaybe(?, activationPending);
                dynamicAssert(valid, "activation response is not outstanding");
                if (valid) activationPending <= tagged Invalid;
            endmethod
        endinterface
    endinterface

    interface ReadPortIfc weightPort;
        interface ReadRequestSourceIfc requests;
            method Bool valid = isValid(weightOffered);
            method AquaMemoryReadRequest first if (isValid(weightOffered));
                return fromMaybe(?, weightOffered);
            endmethod
            method Action consume
                if (isValid(weightOffered) && !isValid(weightPending));
                weightPending <= tagged Valid fromMaybe(?, weightOffered).tag;
                weightOffered <= tagged Invalid;
            endmethod
        endinterface
        interface ReadResponseSinkIfc responses;
            method Bool ready(AquaMemoryTag tag) =
                isValid(weightPending) && tag == fromMaybe(?, weightPending);
            method Action put(AquaMemoryTag tag);
                Bool valid = isValid(weightPending)
                    && tag == fromMaybe(?, weightPending);
                dynamicAssert(valid, "weight response is not outstanding");
                if (valid) weightPending <= tagged Invalid;
            endmethod
        endinterface
    endinterface

    interface ReadPortIfc blockShiftPort;
        interface ReadRequestSourceIfc requests;
            method Bool valid = isValid(blockOffered);
            method AquaMemoryReadRequest first if (isValid(blockOffered));
                return fromMaybe(?, blockOffered);
            endmethod
            method Action consume
                if (isValid(blockOffered) && !isValid(blockPending));
                blockPending <= tagged Valid fromMaybe(?, blockOffered).tag;
                blockOffered <= tagged Invalid;
            endmethod
        endinterface
        interface ReadResponseSinkIfc responses;
            method Bool ready(AquaMemoryTag tag) =
                isValid(blockPending) && tag == fromMaybe(?, blockPending);
            method Action put(AquaMemoryTag tag);
                Bool valid = isValid(blockPending)
                    && tag == fromMaybe(?, blockPending);
                dynamicAssert(valid, "block shift response is not outstanding");
                if (valid) begin
                    blockPending <= tagged Invalid;
                    lastBlockKey <= tagged Valid blockScaleReuseKey(
                        fromMaybe(?, active)
                    );
                end
            endmethod
        endinterface
    endinterface

    interface ReadPortIfc rowShiftPort;
        interface ReadRequestSourceIfc requests;
            method Bool valid = isValid(rowOffered);
            method AquaMemoryReadRequest first if (isValid(rowOffered));
                return fromMaybe(?, rowOffered);
            endmethod
            method Action consume
                if (isValid(rowOffered) && !isValid(rowPending));
                rowPending <= tagged Valid fromMaybe(?, rowOffered).tag;
                rowOffered <= tagged Invalid;
            endmethod
        endinterface
        interface ReadResponseSinkIfc responses;
            method Bool ready(AquaMemoryTag tag) =
                isValid(rowPending) && tag == fromMaybe(?, rowPending);
            method Action put(AquaMemoryTag tag);
                Bool valid = isValid(rowPending)
                    && tag == fromMaybe(?, rowPending);
                dynamicAssert(valid, "row shift response is not outstanding");
                if (valid) begin
                    rowPending <= tagged Invalid;
                    lastRowKey <= tagged Valid rowScaleReuseKey(
                        fromMaybe(?, active)
                    );
                end
            endmethod
        endinterface
    endinterface

    method Bool metadataResponseMaskValid(Vector#(arrayDim, Bool) mask);
        return isValid(active)
            && metadataMaskMatches(mask, fromMaybe(?, active).jCount);
    endmethod

    method Bool completionValid = completions.notEmpty;
    method LoadCompletion completion if (completions.notEmpty);
        return completions.first;
    endmethod
    method Action consumeCompletion if (completions.notEmpty);
        completions.deq;
    endmethod
    method UInt#(64) outstandingCycles = stagingCycles;
endmodule

endpackage
