package LoadResponseRouterTypes;

import AquaMemoryTypes::*;
import LoadControllerTypes::*;

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

endpackage
