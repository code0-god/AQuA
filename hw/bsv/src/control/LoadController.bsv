package LoadController;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryTypes::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import FIFOF::*;
import LoadChannel::*;
import LoadRequestBuilder::*;
import LoadResponseRouter::*;
import SpecialFIFOs::*;
import Vector::*;

interface LoadControllerIfc#(
    numeric type arrayDim,
    numeric type bankCount,
    numeric type metaEntries
);
    method Bool scheduleReady;
    method Action schedule(ProviderLoadWork#(arrayDim) work);

    interface LoadRequestSourceIfc activationRequests;
    interface LoadRequestSourceIfc weightRequests;
    interface LoadRequestSourceIfc blockShiftRequests;
    interface LoadRequestSourceIfc rowScaleRequests;

    method Bool activationResponseReady(AquaMemoryTag tag);
    method Action completeActivation(AquaMemoryTag tag);
    method Bool queuedActivationResponseReady(AquaMemoryTag tag);
    method Action completeQueuedActivation(AquaMemoryTag tag);
    method Bool weightResponseReady(AquaMemoryTag tag);
    method Action completeWeight(AquaMemoryTag tag);
    method Bool queuedWeightResponseReady(AquaMemoryTag tag);
    method Action completeQueuedWeight(AquaMemoryTag tag);
    method Bool blockShiftResponseReady(AquaMemoryTag tag);
    method Action completeBlockShift(AquaMemoryTag tag);
    method Bool queuedBlockShiftResponseReady(AquaMemoryTag tag);
    method Action completeQueuedBlockShift(AquaMemoryTag tag);
    method Bool rowScaleResponseReady(AquaMemoryTag tag);
    method Action completeRowScale(AquaMemoryTag tag);
    method Bool queuedRowScaleResponseReady(AquaMemoryTag tag);
    method Action completeQueuedRowScale(AquaMemoryTag tag);

    method Bool metadataResponseMaskValid(Vector#(arrayDim, Bool) mask);

    method Bool completionValid;
    method LoadCompletion completion;
    method Action consumeCompletion;
    method UInt#(64) outstandingCycles;
endinterface

function Action validateProviderLoadWork(
    ProviderLoadWork#(arrayDim) work,
    Integer bankCount,
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
            zeroExtend(activationBaseRow) * fromInteger(bankCount)
            + zeroExtend(activationBaseBank)
            + zeroExtend(iCount == 0 ? 0 : iCount - 1);
        UInt#(40) weightLinearEnd =
            zeroExtend(weightBaseRow) * fromInteger(bankCount)
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
        dynamicAssert(activationBaseBank < fromInteger(bankCount),
                      "activation base bank exceeds configured banks");
        dynamicAssert(weightBaseBank < fromInteger(bankCount),
                      "weight base bank exceeds configured banks");
        dynamicAssert(
            activationLinearEnd / fromInteger(bankCount)
                < fromInteger(2 ** 16),
            "activation local row range overflow"
        );
        dynamicAssert(
            weightLinearEnd / fromInteger(bankCount)
                < fromInteger(2 ** 16),
            "weight local row range overflow"
        );
        dynamicAssert(work.blockShiftDestination.region == LocalHp1Meta,
                      "block shift has wrong local region");
        dynamicAssert(work.rowScaleDestination.region == LocalHp1Meta,
                      "row scale has wrong local region");
        dynamicAssert(blockMetadataBank == 0,
                      "block shift metadata bank must be zero");
        dynamicAssert(rowMetadataBank == 0,
                      "row scale metadata bank must be zero");
        dynamicAssert(blockMetadataRow < fromInteger(metaEntries),
                      "block shift metadata row out of bounds");
        dynamicAssert(rowMetadataRow < fromInteger(metaEntries),
                      "row scale metadata row out of bounds");
    endaction
endfunction

module mkLoadController(LoadControllerIfc#(
    arrayDim,
    bankCount,
    metaEntries
)) provisos (
    Add#(lanePadding, TLog#(arrayDim), 32),
    Add#(laneTagPadding, TLog#(arrayDim), 40)
);
    LoadResponseRouterIfc#(arrayDim, bankCount) router
        <- mkLoadResponseRouter;
    FIFOF#(LoadCompletion) completions <- mkPipelineFIFOF;
    Reg#(Maybe#(ProviderLoadWork#(arrayDim))) active
        <- mkReg(tagged Invalid);
    Reg#(ArrayCount) activationIssue <- mkReg(0);
    Reg#(ArrayCount) weightIssue <- mkReg(0);
    Reg#(Bool) blockNeeded <- mkReg(False);
    Reg#(Bool) blockIssued <- mkReg(False);
    Reg#(Bool) rowNeeded <- mkReg(False);
    Reg#(Bool) rowIssued <- mkReg(False);
    Reg#(UInt#(64)) stagingCycles <- mkReg(0);

    staticAssert(
        valueOf(arrayDim) == 16
        || valueOf(arrayDim) == 32
        || valueOf(arrayDim) == 64,
        "load controller array dimension must be 16, 32, or 64"
    );

    rule issueActivation (
        isValid(active)
        && activationIssue < fromMaybe(?, active).iCount
        && router.activationIssueReady
    );
        let work = fromMaybe(?, active);
        MatrixExtent index = zeroExtend(activationIssue);
        router.issueActivation(
            truncate(pack(index)),
            LoadRequestBuilder::activationRequest(
                work,
                index,
                valueOf(bankCount)
            )
        );
        activationIssue <= activationIssue + 1;
    endrule

    rule issueWeight (
        isValid(active)
        && weightIssue < fromMaybe(?, active).jCount
        && router.weightIssueReady
    );
        let work = fromMaybe(?, active);
        MatrixExtent index = zeroExtend(weightIssue);
        router.issueWeight(
            truncate(pack(index)),
            LoadRequestBuilder::weightRequest(
                work,
                index,
                valueOf(bankCount)
            )
        );
        weightIssue <= weightIssue + 1;
    endrule

    rule issueBlockShift (
        isValid(active)
        && blockNeeded
        && !blockIssued
        && router.blockIssueReady
    );
        router.issueBlock(
            LoadRequestBuilder::blockShiftRequest(fromMaybe(?, active))
        );
        blockIssued <= True;
    endrule

    rule issueRowScale (
        isValid(active)
        && rowNeeded
        && !rowIssued
        && router.rowIssueReady
    );
        router.issueRow(
            LoadRequestBuilder::rowScaleRequest(fromMaybe(?, active))
        );
        rowIssued <= True;
    endrule

    rule completeLoad (
        isValid(active)
        && activationIssue == fromMaybe(?, active).iCount
        && weightIssue == fromMaybe(?, active).jCount
        && blockIssued
        && rowIssued
        && router.finishReady
        && completions.notFull
    );
        let work = fromMaybe(?, active);
        completions.enq(LoadCompletion {
            jobId: work.jobId,
            stripeId: work.stripeId,
            arrayWorkId: work.arrayWorkId,
            fragmentId: work.fragmentId
        });
        router.finish;
        active <= tagged Invalid;
    endrule

    rule countOutstanding(isValid(active));
        stagingCycles <= stagingCycles + 1;
    endrule

    method Bool scheduleReady =
        !isValid(active)
        && completions.notFull
        && router.startReady;

    method Action schedule(ProviderLoadWork#(arrayDim) work)
        if (
            !isValid(active)
            && completions.notFull
            && router.startReady
        );
        validateProviderLoadWork(
            work,
            valueOf(bankCount),
            valueOf(metaEntries)
        );
        active <= tagged Valid work;
        activationIssue <= 0;
        weightIssue <= 0;
        blockNeeded <= router.blockShiftNeeded(work);
        blockIssued <= !router.blockShiftNeeded(work);
        rowNeeded <= router.rowScaleNeeded(work);
        rowIssued <= !router.rowScaleNeeded(work);
        router.start(work);
    endmethod

    interface activationRequests = router.activationRequests;
    interface weightRequests = router.weightRequests;
    interface blockShiftRequests = router.blockShiftRequests;
    interface rowScaleRequests = router.rowScaleRequests;

    method Bool activationResponseReady(AquaMemoryTag tag) =
        router.activationResponseReady(tag);
    method Action completeActivation(AquaMemoryTag tag);
        Bool valid = router.activationResponseReady(tag);
        dynamicAssert(valid, "activation response is not outstanding");
        if (valid) router.completeActivation(tag);
    endmethod
    method Bool queuedActivationResponseReady(AquaMemoryTag tag) =
        router.queuedActivationResponseReady(tag);
    method Action completeQueuedActivation(AquaMemoryTag tag);
        Bool valid = router.queuedActivationResponseReady(tag);
        dynamicAssert(valid, "queued activation response mismatch");
        if (valid) router.completeQueuedActivation(tag);
    endmethod
    method Bool weightResponseReady(AquaMemoryTag tag) =
        router.weightResponseReady(tag);
    method Action completeWeight(AquaMemoryTag tag);
        Bool valid = router.weightResponseReady(tag);
        dynamicAssert(valid, "weight response is not outstanding");
        if (valid) router.completeWeight(tag);
    endmethod
    method Bool queuedWeightResponseReady(AquaMemoryTag tag) =
        router.queuedWeightResponseReady(tag);
    method Action completeQueuedWeight(AquaMemoryTag tag);
        Bool valid = router.queuedWeightResponseReady(tag);
        dynamicAssert(valid, "queued weight response mismatch");
        if (valid) router.completeQueuedWeight(tag);
    endmethod
    method Bool blockShiftResponseReady(AquaMemoryTag tag) =
        router.blockShiftResponseReady(tag);
    method Action completeBlockShift(AquaMemoryTag tag);
        Bool valid = router.blockShiftResponseReady(tag);
        dynamicAssert(valid, "block shift response is not outstanding");
        if (valid) router.completeBlockShift(tag);
    endmethod
    method Bool queuedBlockShiftResponseReady(AquaMemoryTag tag) =
        router.queuedBlockShiftResponseReady(tag);
    method Action completeQueuedBlockShift(AquaMemoryTag tag);
        Bool valid = router.queuedBlockShiftResponseReady(tag);
        dynamicAssert(valid, "queued block shift response mismatch");
        if (valid) router.completeQueuedBlockShift(tag);
    endmethod
    method Bool rowScaleResponseReady(AquaMemoryTag tag) =
        router.rowScaleResponseReady(tag);
    method Action completeRowScale(AquaMemoryTag tag);
        Bool valid = router.rowScaleResponseReady(tag);
        dynamicAssert(valid, "row scale response is not outstanding");
        if (valid) router.completeRowScale(tag);
    endmethod
    method Bool queuedRowScaleResponseReady(AquaMemoryTag tag) =
        router.queuedRowScaleResponseReady(tag);
    method Action completeQueuedRowScale(AquaMemoryTag tag);
        Bool valid = router.queuedRowScaleResponseReady(tag);
        dynamicAssert(valid, "queued row scale response mismatch");
        if (valid) router.completeQueuedRowScale(tag);
    endmethod

    method Bool metadataResponseMaskValid(Vector#(arrayDim, Bool) mask) =
        router.metadataResponseMaskValid(mask);

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
