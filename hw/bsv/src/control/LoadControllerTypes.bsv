package LoadControllerTypes;

import AquaMemoryTypes::*;
import AquaTypes::*;

interface LoadRequestSourceIfc;
    method Bool requestValid;
    method AquaMemoryReadRequest request;
    method Action consumeRequest;
endinterface

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

    method Bool completionValid;
    method LoadCompletion completion;
    method Action consumeCompletion;
    method UInt#(64) outstandingCycles;
endinterface

endpackage
