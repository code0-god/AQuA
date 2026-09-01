package AquaMemorySubsystemTypes;

import AccumulatorMem::*;
import AquaMemoryTypes::*;
import AquaTypes::*;
import Hp1MetaMem::*;
import ScratchpadBank::*;
import Vector::*;

interface AquaMemorySubsystemIfc#(
    numeric type arrayDim,
    numeric type spadBanks,
    numeric type spadRows,
    numeric type metaEntries,
    numeric type activationWidth,
    numeric type weightWidth,
    numeric type shiftWidth,
    numeric type accRows,
    numeric type accWidth
);
    method Bool loadReady;
    method Action scheduleLoad(ProviderLoadWork#(arrayDim) work);

    method Bool activationRequestValid;
    method AquaMemoryReadRequest activationRequest;
    method Action consumeActivationRequest;
    method Bool weightRequestValid;
    method AquaMemoryReadRequest weightRequest;
    method Action consumeWeightRequest;
    method Bool blockShiftRequestValid;
    method AquaMemoryReadRequest blockShiftRequest;
    method Action consumeBlockShiftRequest;
    method Bool rowScaleRequestValid;
    method AquaMemoryReadRequest rowScaleRequest;
    method Action consumeRowScaleRequest;

    method Action putActivationResponse(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Int#(activationWidth))
        ) response
    );
    method Bool activationResponseReady(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Int#(activationWidth))
        ) response
    );
    method Bool queuedActivationResponseReady(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Int#(activationWidth))
        ) response
    );
    method Action putQueuedActivationResponse(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Int#(activationWidth))
        ) response
    );
    method Action putWeightResponse(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Bit#(weightWidth))
        ) response
    );
    method Bool weightResponseReady(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Bit#(weightWidth))
        ) response
    );
    method Bool queuedWeightResponseReady(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Bit#(weightWidth))
        ) response
    );
    method Action putQueuedWeightResponse(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Bit#(weightWidth))
        ) response
    );
    method Action putBlockShiftResponse(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
    method Bool blockShiftResponseReady(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
    method Bool queuedBlockShiftResponseReady(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
    method Action putQueuedBlockShiftResponse(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
    method Action putRowScaleResponse(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
    method Bool rowScaleResponseReady(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
    method Bool queuedRowScaleResponseReady(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
    method Action putQueuedRowScaleResponse(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );

    method Bool loadCompletionValid;
    method LoadCompletion loadCompletion;
    method Action consumeLoadCompletion;

    method Bool storeReady;
    method Action scheduleStore(StoreWork#(arrayDim) work);
    method Bool outputRequestValid;
    method AquaMemoryWriteRequest#(accWidth) outputRequest;
    method Action consumeOutputRequest;
    method Bool outputAckReady(AquaMemoryWriteAck acknowledgement);
    method Action putOutputAck(AquaMemoryWriteAck acknowledgement);
    method Bool storeCompletionValid;
    method StoreCompletion storeCompletion;
    method Action consumeStoreCompletion;

    interface Vector#(
        spadBanks,
        ScratchpadBankIfc#(
            spadRows,
            arrayDim,
            Int#(activationWidth)
        )
    ) activationBanks;
    interface Vector#(
        spadBanks,
        ScratchpadBankIfc#(
            spadRows,
            arrayDim,
            Bit#(weightWidth)
        )
    ) weightBanks;
    interface Hp1MetaMemIfc#(metaEntries, shiftWidth) hp1Meta;
    interface AccumulatorMemIfc#(arrayDim, accRows, accWidth) accumulator;
endinterface

endpackage
