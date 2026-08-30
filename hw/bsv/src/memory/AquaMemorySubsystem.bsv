package AquaMemorySubsystem;

import AccumulatorMem::*;
import AquaMemorySubsystemTypes::*;
import AquaMemoryTypes::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import LoadController::*;
import LoadControllerTypes::*;
import MetadataResponseStager::*;
import ScratchpadResponseStager::*;
import ScratchpadResponseStagerTypes::*;
import StoreController::*;

module mkAquaMemorySubsystem(
    AquaMemorySubsystemIfc#(
        arrayDim,
        spadBanks,
        spadRows,
        metaEntries,
        activationWidth,
        weightWidth,
        shiftWidth,
        accRows,
        accWidth
    )
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32),
    Add#(lanePadding, TLog#(arrayDim), 32),
    Add#(laneTagPadding, TLog#(arrayDim), 40),
    Add#(accBankPadding, TLog#(TAdd#(arrayDim, 1)), 8),
    Add#(accRowPadding, TLog#(TAdd#(accRows, 1)), 16),
    Add#(spadBankPadding, TLog#(spadBanks), 32),
    Add#(spadRowPadding, TLog#(TAdd#(spadRows, 1)), 32),
    Add#(metaPadding, TLog#(TAdd#(metaEntries, 1)), 32)
);
    LoadControllerIfc#(arrayDim, spadBanks, metaEntries) load
        <- mkLoadController;
    ScratchpadResponseStagerIfc#(
        arrayDim,
        spadBanks,
        spadRows,
        activationWidth,
        weightWidth
    ) scratchpads <- mkScratchpadResponseStager(load);
    MetadataResponseStagerIfc#(metaEntries, shiftWidth) metadata
        <- mkMetadataResponseStager(load);
    AccumulatorMemIfc#(arrayDim, accRows, accWidth) accumulators
        <- mkAccumulatorMem;
    StoreControllerIfc#(arrayDim, arrayDim, accRows, accWidth) store
        <- mkStoreController(accumulators);

    method Bool loadReady = load.scheduleReady;
    method Action scheduleLoad(ProviderLoadWork#(arrayDim) work);
        load.schedule(work);
    endmethod

    method Bool activationRequestValid =
        load.activationRequests.requestValid;
    method AquaMemoryReadRequest activationRequest
        if (load.activationRequests.requestValid);
        return load.activationRequests.request;
    endmethod
    method Action consumeActivationRequest
        if (load.activationRequests.requestValid);
        load.activationRequests.consumeRequest;
    endmethod
    method Bool weightRequestValid = load.weightRequests.requestValid;
    method AquaMemoryReadRequest weightRequest
        if (load.weightRequests.requestValid);
        return load.weightRequests.request;
    endmethod
    method Action consumeWeightRequest if (load.weightRequests.requestValid);
        load.weightRequests.consumeRequest;
    endmethod
    method Bool blockShiftRequestValid =
        load.blockShiftRequests.requestValid;
    method AquaMemoryReadRequest blockShiftRequest
        if (load.blockShiftRequests.requestValid);
        return load.blockShiftRequests.request;
    endmethod
    method Action consumeBlockShiftRequest
        if (load.blockShiftRequests.requestValid);
        load.blockShiftRequests.consumeRequest;
    endmethod
    method Bool rowScaleRequestValid =
        load.rowScaleRequests.requestValid;
    method AquaMemoryReadRequest rowScaleRequest
        if (load.rowScaleRequests.requestValid);
        return load.rowScaleRequests.request;
    endmethod
    method Action consumeRowScaleRequest
        if (load.rowScaleRequests.requestValid);
        load.rowScaleRequests.consumeRequest;
    endmethod

    method Bool activationResponseReady(
        ActivationMemoryResponse#(arrayDim, activationWidth) response
    ) =
        scratchpads.activationResponseReady(response);
    method Action putActivationResponse(
        ActivationMemoryResponse#(arrayDim, activationWidth) response
    );
        scratchpads.putActivationResponse(response);
    endmethod
    method Bool queuedActivationResponseReady(
        ActivationMemoryResponse#(arrayDim, activationWidth) response
    ) =
        scratchpads.queuedActivationResponseReady(response);
    method Action putQueuedActivationResponse(
        ActivationMemoryResponse#(arrayDim, activationWidth) response
    );
        scratchpads.putQueuedActivationResponse(response);
    endmethod
    method Bool weightResponseReady(
        WeightMemoryResponse#(arrayDim, weightWidth) response
    ) =
        scratchpads.weightResponseReady(response);
    method Action putWeightResponse(
        WeightMemoryResponse#(arrayDim, weightWidth) response
    );
        scratchpads.putWeightResponse(response);
    endmethod
    method Bool queuedWeightResponseReady(
        WeightMemoryResponse#(arrayDim, weightWidth) response
    ) =
        scratchpads.queuedWeightResponseReady(response);
    method Action putQueuedWeightResponse(
        WeightMemoryResponse#(arrayDim, weightWidth) response
    );
        scratchpads.putQueuedWeightResponse(response);
    endmethod
    method Bool blockShiftResponseReady(
        BlockShiftMemoryResponse#(shiftWidth) response
    ) =
        metadata.blockShiftResponseReady(response);
    method Action putBlockShiftResponse(
        BlockShiftMemoryResponse#(shiftWidth) response
    );
        metadata.putBlockShiftResponse(response);
    endmethod
    method Bool queuedBlockShiftResponseReady(
        BlockShiftMemoryResponse#(shiftWidth) response
    ) =
        metadata.queuedBlockShiftResponseReady(response);
    method Action putQueuedBlockShiftResponse(
        BlockShiftMemoryResponse#(shiftWidth) response
    );
        metadata.putQueuedBlockShiftResponse(response);
    endmethod
    method Bool rowScaleResponseReady(
        RowScaleMemoryResponse#(shiftWidth) response
    ) =
        metadata.rowScaleResponseReady(response);
    method Action putRowScaleResponse(
        RowScaleMemoryResponse#(shiftWidth) response
    );
        metadata.putRowScaleResponse(response);
    endmethod
    method Bool queuedRowScaleResponseReady(
        RowScaleMemoryResponse#(shiftWidth) response
    ) =
        metadata.queuedRowScaleResponseReady(response);
    method Action putQueuedRowScaleResponse(
        RowScaleMemoryResponse#(shiftWidth) response
    );
        metadata.putQueuedRowScaleResponse(response);
    endmethod

    method Bool loadCompletionValid = load.completionValid;
    method LoadCompletion loadCompletion if (load.completionValid);
        return load.completion;
    endmethod
    method Action consumeLoadCompletion if (load.completionValid);
        load.consumeCompletion;
    endmethod

    method Bool storeReady = store.startReady;
    method Action scheduleStore(StoreWork#(arrayDim) work);
        store.start(work);
    endmethod
    method Bool outputRequestValid = store.outputRequestValid;
    method AquaMemoryWriteRequest#(accWidth) outputRequest
        if (store.outputRequestValid);
        return store.outputRequest;
    endmethod
    method Action consumeOutputRequest if (store.outputRequestValid);
        store.consumeOutputRequest;
    endmethod
    method Bool outputAckReady(AquaMemoryWriteAck acknowledgement);
        return store.outputAckReady(acknowledgement);
    endmethod
    method Action putOutputAck(AquaMemoryWriteAck acknowledgement);
        store.putOutputAck(acknowledgement);
    endmethod
    method Bool storeCompletionValid = store.completionValid;
    method StoreCompletion storeCompletion if (store.completionValid);
        return store.completion;
    endmethod
    method Action consumeStoreCompletion if (store.completionValid);
        store.consumeCompletion;
    endmethod

    interface activationBanks = scratchpads.activationBanks;
    interface weightBanks = scratchpads.weightBanks;
    interface hp1Meta = metadata.hp1Meta;
    interface accumulator = accumulators;
endmodule

endpackage
