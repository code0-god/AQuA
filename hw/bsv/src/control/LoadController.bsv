package LoadController;

import Assert::*;
import AquaMemoryTypes::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import FIFOF::*;
import LoadControllerTypes::*;
import LoadRequestBuilder::*;
import LoadResponseRouter::*;
import LoadResponseRouterTypes::*;
import LoadWorkValidation::*;
import SpecialFIFOs::*;

module mkLoadController(LoadControllerIfc#(
    arrayDim,
    bankCount,
    metaEntries
)) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32),
    Add#(lanePadding, TLog#(arrayDim), 32),
    Add#(laneTagPadding, TLog#(arrayDim), 40)
);
    LoadResponseRouterIfc#(arrayDim, bankCount) router
        <- mkLoadResponseRouter;
    FIFOF#(LoadCompletion) completions <- mkPipelineFIFOF;
    Reg#(Maybe#(ProviderLoadWork#(arrayDim))) active
        <- mkReg(tagged Invalid);
    Reg#(ArrayExtent#(arrayDim)) activationIssue <- mkReg(0);
    Reg#(ArrayExtent#(arrayDim)) weightIssue <- mkReg(0);
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
            macroTileId: work.macroTileId,
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
