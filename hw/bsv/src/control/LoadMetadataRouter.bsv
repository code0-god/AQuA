package LoadMetadataRouter;

import Assert::*;
import AquaMemoryTypes::*;
import LoadChannel::*;
import LoadRequestBuilder::*;

interface LoadMetadataRouterIfc#(numeric type arrayDim);
    method Bool startReady;
    method Action start(ProviderLoadWork#(arrayDim) work);
    method Action finish;
    method Bool finishReady;
    method Bool allEmpty;

    method Bool blockIssueReady;
    method Action issueBlock(AquaMemoryReadRequest request);
    method Bool rowIssueReady;
    method Action issueRow(AquaMemoryReadRequest request);
    method Bool rowScaleNeeded(ProviderLoadWork#(arrayDim) work);
    method Bool blockShiftNeeded(ProviderLoadWork#(arrayDim) work);

    interface LoadRequestSourceIfc blockShiftRequests;
    interface LoadRequestSourceIfc rowScaleRequests;

    method Bool blockShiftResponseReady(AquaMemoryTag tag);
    method Action completeBlockShift(AquaMemoryTag tag);
    method Bool queuedBlockShiftResponseReady(AquaMemoryTag tag);
    method Action completeQueuedBlockShift(AquaMemoryTag tag);
    method Bool rowScaleResponseReady(AquaMemoryTag tag);
    method Action completeRowScale(AquaMemoryTag tag);
    method Bool queuedRowScaleResponseReady(AquaMemoryTag tag);
    method Action completeQueuedRowScale(AquaMemoryTag tag);
endinterface

module mkLoadMetadataRouter(LoadMetadataRouterIfc#(arrayDim))
    provisos (
        Add#(laneTagPadding, TLog#(arrayDim), 40)
    );
    LoadChannelIfc#(arrayDim) blockChannel <- mkLoadChannel;
    LoadChannelIfc#(arrayDim) rowChannel <- mkLoadChannel;
    Reg#(Maybe#(ProviderLoadWork#(arrayDim))) active
        <- mkReg(tagged Invalid);
    Reg#(Maybe#(RowScaleReuseKey)) lastRowKey
        <- mkReg(tagged Invalid);
    Reg#(Maybe#(BlockScaleReuseKey)) lastBlockKey
        <- mkReg(tagged Invalid);
    PulseWire blockAccepted <- mkPulseWire;
    PulseWire rowAccepted <- mkPulseWire;

    method Bool startReady =
        !isValid(active)
        && blockChannel.empty
        && rowChannel.empty;
    method Action start(ProviderLoadWork#(arrayDim) work)
        if (!isValid(active) && blockChannel.empty && rowChannel.empty);
        active <= tagged Valid work;
    endmethod
    method Action finish
        if (isValid(active) && blockChannel.empty && rowChannel.empty);
        active <= tagged Invalid;
    endmethod
    method Bool finishReady =
        isValid(active)
        && blockChannel.empty
        && rowChannel.empty
        && !blockAccepted
        && !rowAccepted;
    method Bool allEmpty = blockChannel.empty && rowChannel.empty;

    method Bool blockIssueReady = blockChannel.issueReady;
    method Action issueBlock(AquaMemoryReadRequest request);
        blockChannel.issue(0, request);
    endmethod
    method Bool rowIssueReady = rowChannel.issueReady;
    method Action issueRow(AquaMemoryReadRequest request);
        rowChannel.issue(0, request);
    endmethod
    method Bool rowScaleNeeded(ProviderLoadWork#(arrayDim) work);
        let key = rowScaleReuseKey(work);
        return !isValid(lastRowKey) || fromMaybe(?, lastRowKey) != key;
    endmethod
    method Bool blockShiftNeeded(ProviderLoadWork#(arrayDim) work);
        let key = blockScaleReuseKey(work);
        return !isValid(lastBlockKey) || fromMaybe(?, lastBlockKey) != key;
    endmethod

    interface blockShiftRequests = blockChannel.requests;
    interface rowScaleRequests = rowChannel.requests;

    method Bool blockShiftResponseReady(AquaMemoryTag tag);
        return
            isValid(active)
            && blockChannel.isPending(0)
            && matchesBlockShiftResponse(fromMaybe(?, active), tag);
    endmethod
    method Action completeBlockShift(AquaMemoryTag tag);
        Bool valid =
            isValid(active)
            && blockChannel.isPending(0)
            && matchesBlockShiftResponse(fromMaybe(?, active), tag);
        dynamicAssert(valid, "block shift response is not outstanding");
        if (valid) begin
            let work = fromMaybe(?, active);
            blockChannel.complete(0);
            lastBlockKey <= tagged Valid blockScaleReuseKey(work);
            blockAccepted.send;
        end
    endmethod
    method Bool queuedBlockShiftResponseReady(AquaMemoryTag tag);
        return
            isValid(active)
            && blockChannel.queuedTagMatches(tag)
            && matchesBlockShiftResponse(fromMaybe(?, active), tag);
    endmethod
    method Action completeQueuedBlockShift(AquaMemoryTag tag);
        Bool valid =
            isValid(active)
            && blockChannel.queuedTagMatches(tag)
            && matchesBlockShiftResponse(fromMaybe(?, active), tag);
        dynamicAssert(valid, "queued block shift response mismatch");
        if (valid) begin
            let work = fromMaybe(?, active);
            blockChannel.completeQueued(0);
            lastBlockKey <= tagged Valid blockScaleReuseKey(work);
            blockAccepted.send;
        end
    endmethod

    method Bool rowScaleResponseReady(AquaMemoryTag tag);
        return
            isValid(active)
            && rowChannel.isPending(0)
            && matchesRowScaleResponse(fromMaybe(?, active), tag);
    endmethod
    method Action completeRowScale(AquaMemoryTag tag);
        Bool valid =
            isValid(active)
            && rowChannel.isPending(0)
            && matchesRowScaleResponse(fromMaybe(?, active), tag);
        dynamicAssert(valid, "row scale response is not outstanding");
        if (valid) begin
            let work = fromMaybe(?, active);
            rowChannel.complete(0);
            lastRowKey <= tagged Valid rowScaleReuseKey(work);
            rowAccepted.send;
        end
    endmethod
    method Bool queuedRowScaleResponseReady(AquaMemoryTag tag);
        return
            isValid(active)
            && rowChannel.queuedTagMatches(tag)
            && matchesRowScaleResponse(fromMaybe(?, active), tag);
    endmethod
    method Action completeQueuedRowScale(AquaMemoryTag tag);
        Bool valid =
            isValid(active)
            && rowChannel.queuedTagMatches(tag)
            && matchesRowScaleResponse(fromMaybe(?, active), tag);
        dynamicAssert(valid, "queued row scale response mismatch");
        if (valid) begin
            let work = fromMaybe(?, active);
            rowChannel.completeQueued(0);
            lastRowKey <= tagged Valid rowScaleReuseKey(work);
            rowAccepted.send;
        end
    endmethod
endmodule

endpackage
