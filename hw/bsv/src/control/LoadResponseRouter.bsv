package LoadResponseRouter;

import Assert::*;
import AquaMemoryTypes::*;
import AquaTypes::*;
import LoadChannel::*;
import LoadMetadataRouter::*;
import LoadRequestBuilder::*;

interface LoadResponseRouterIfc#(
    numeric type arrayDim,
    numeric type bankCount
);
    method Bool startReady;
    method Action start(ProviderLoadWork#(arrayDim) work);
    method Action finish;

    method Bool activationIssueReady;
    method Action issueActivation(
        Bit#(TLog#(arrayDim)) lane,
        AquaMemoryReadRequest request
    );
    method Bool weightIssueReady;
    method Action issueWeight(
        Bit#(TLog#(arrayDim)) lane,
        AquaMemoryReadRequest request
    );
    method Bool blockIssueReady;
    method Action issueBlock(AquaMemoryReadRequest request);
    method Bool rowIssueReady;
    method Action issueRow(AquaMemoryReadRequest request);

    method Bool rowScaleNeeded(ProviderLoadWork#(arrayDim) work);
    method Bool blockShiftNeeded(ProviderLoadWork#(arrayDim) work);
    method Bool allEmpty;
    method Bool finishReady;

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
endinterface

module mkLoadResponseRouter(
    LoadResponseRouterIfc#(arrayDim, bankCount)
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32),
    Add#(lanePadding, TLog#(arrayDim), 32),
    Add#(laneTagPadding, TLog#(arrayDim), 40)
);
    LoadChannelIfc#(arrayDim) activationChannel <- mkLoadChannel;
    LoadChannelIfc#(arrayDim) weightChannel <- mkLoadChannel;
    LoadMetadataRouterIfc#(arrayDim) metadata <- mkLoadMetadataRouter;
    Reg#(Maybe#(ProviderLoadWork#(arrayDim))) active
        <- mkReg(tagged Invalid);
    PulseWire activationAccepted <- mkPulseWire;
    PulseWire weightAccepted <- mkPulseWire;

    method Bool startReady =
        !isValid(active)
        && activationChannel.empty
        && weightChannel.empty
        && metadata.startReady;

    method Action start(ProviderLoadWork#(arrayDim) work)
        if (
            !isValid(active)
            && activationChannel.empty
            && weightChannel.empty
            && metadata.startReady
            && !activationAccepted
            && !weightAccepted
        );
        active <= tagged Valid work;
        metadata.start(work);
    endmethod

    method Action finish
        if (
            isValid(active)
            && activationChannel.empty
            && weightChannel.empty
            && metadata.finishReady
        );
        active <= tagged Invalid;
        metadata.finish;
    endmethod

    method Bool activationIssueReady = activationChannel.issueReady;
    method Action issueActivation(
        Bit#(TLog#(arrayDim)) lane,
        AquaMemoryReadRequest request
    );
        activationChannel.issue(lane, request);
    endmethod
    method Bool weightIssueReady = weightChannel.issueReady;
    method Action issueWeight(
        Bit#(TLog#(arrayDim)) lane,
        AquaMemoryReadRequest request
    );
        weightChannel.issue(lane, request);
    endmethod
    method Bool blockIssueReady = metadata.blockIssueReady;
    method Action issueBlock(AquaMemoryReadRequest request);
        metadata.issueBlock(request);
    endmethod
    method Bool rowIssueReady = metadata.rowIssueReady;
    method Action issueRow(AquaMemoryReadRequest request);
        metadata.issueRow(request);
    endmethod

    method Bool rowScaleNeeded(ProviderLoadWork#(arrayDim) work) =
        metadata.rowScaleNeeded(work);
    method Bool blockShiftNeeded(ProviderLoadWork#(arrayDim) work) =
        metadata.blockShiftNeeded(work);
    method Bool allEmpty =
        activationChannel.empty
        && weightChannel.empty
        && metadata.allEmpty;
    method Bool finishReady =
        isValid(active)
        && activationChannel.empty
        && weightChannel.empty
        && metadata.finishReady
        && !activationAccepted
        && !weightAccepted;

    interface activationRequests = activationChannel.requests;
    interface weightRequests = weightChannel.requests;
    interface blockShiftRequests = metadata.blockShiftRequests;
    interface rowScaleRequests = metadata.rowScaleRequests;

    method Bool activationResponseReady(AquaMemoryTag tag);
        if (!isValid(active)) begin
            return False;
        end
        else begin
            let work = fromMaybe(?, active);
            let lane = responseLane(work, tag);
            return activationChannel.isPending(lane)
                && matchesActivationResponse(
                    work,
                    tag,
                    valueOf(bankCount)
                );
        end
    endmethod
    method Action completeActivation(AquaMemoryTag tag);
        if (isValid(active)) begin
            let work = fromMaybe(?, active);
            let lane = responseLane(work, tag);
            Bool valid =
                activationChannel.isPending(lane)
                && matchesActivationResponse(
                    work,
                    tag,
                    valueOf(bankCount)
                );
            dynamicAssert(valid, "activation response is not outstanding");
            if (valid) begin
                activationChannel.complete(lane);
                activationAccepted.send;
            end
        end
        else begin
            dynamicAssert(False, "activation response has no active work");
        end
    endmethod
    method Bool queuedActivationResponseReady(AquaMemoryTag tag);
        return
            isValid(active)
            && activationChannel.queuedTagMatches(tag)
            && matchesActivationResponse(
                fromMaybe(?, active),
                tag,
                valueOf(bankCount)
            );
    endmethod
    method Action completeQueuedActivation(AquaMemoryTag tag);
        Bool valid =
            isValid(active)
            && activationChannel.queuedTagMatches(tag)
            && matchesActivationResponse(
                fromMaybe(?, active),
                tag,
                valueOf(bankCount)
            );
        dynamicAssert(valid, "queued activation response mismatch");
        if (valid) begin
            let work = fromMaybe(?, active);
            activationChannel.completeQueued(responseLane(work, tag));
            activationAccepted.send;
        end
    endmethod

    method Bool weightResponseReady(AquaMemoryTag tag);
        if (!isValid(active)) begin
            return False;
        end
        else begin
            let work = fromMaybe(?, active);
            let lane = responseLane(work, tag);
            return weightChannel.isPending(lane)
                && matchesWeightResponse(work, tag, valueOf(bankCount));
        end
    endmethod
    method Action completeWeight(AquaMemoryTag tag);
        if (isValid(active)) begin
            let work = fromMaybe(?, active);
            let lane = responseLane(work, tag);
            Bool valid =
                weightChannel.isPending(lane)
                && matchesWeightResponse(
                    work,
                    tag,
                    valueOf(bankCount)
                );
            dynamicAssert(valid, "weight response is not outstanding");
            if (valid) begin
                weightChannel.complete(lane);
                weightAccepted.send;
            end
        end
        else begin
            dynamicAssert(False, "weight response has no active work");
        end
    endmethod
    method Bool queuedWeightResponseReady(AquaMemoryTag tag);
        return
            isValid(active)
            && weightChannel.queuedTagMatches(tag)
            && matchesWeightResponse(
                fromMaybe(?, active),
                tag,
                valueOf(bankCount)
            );
    endmethod
    method Action completeQueuedWeight(AquaMemoryTag tag);
        Bool valid =
            isValid(active)
            && weightChannel.queuedTagMatches(tag)
            && matchesWeightResponse(
                fromMaybe(?, active),
                tag,
                valueOf(bankCount)
            );
        dynamicAssert(valid, "queued weight response mismatch");
        if (valid) begin
            let work = fromMaybe(?, active);
            weightChannel.completeQueued(responseLane(work, tag));
            weightAccepted.send;
        end
    endmethod

    method Bool blockShiftResponseReady(AquaMemoryTag tag) =
        metadata.blockShiftResponseReady(tag);
    method Action completeBlockShift(AquaMemoryTag tag);
        metadata.completeBlockShift(tag);
    endmethod
    method Bool queuedBlockShiftResponseReady(AquaMemoryTag tag) =
        metadata.queuedBlockShiftResponseReady(tag);
    method Action completeQueuedBlockShift(AquaMemoryTag tag);
        metadata.completeQueuedBlockShift(tag);
    endmethod

    method Bool rowScaleResponseReady(AquaMemoryTag tag) =
        metadata.rowScaleResponseReady(tag);
    method Action completeRowScale(AquaMemoryTag tag);
        metadata.completeRowScale(tag);
    endmethod
    method Bool queuedRowScaleResponseReady(AquaMemoryTag tag) =
        metadata.queuedRowScaleResponseReady(tag);
    method Action completeQueuedRowScale(AquaMemoryTag tag);
        metadata.completeQueuedRowScale(tag);
    endmethod
endmodule

endpackage
