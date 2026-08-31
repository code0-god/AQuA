package ScratchpadResponseStager;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryTypes::*;
import LoadController::*;
import Scratchpad::*;
import Vector::*;

function UInt#(32) scratchpadLocalBank(AquaMemoryTag tag);
    return zeroExtend(unpack(tag.localDestination.bank));
endfunction

function UInt#(32) scratchpadLocalRow(AquaMemoryTag tag);
    return zeroExtend(unpack(tag.localDestination.row));
endfunction

function Bool validScratchpadResponse(
    AquaMemoryTag tag,
    AquaMemoryKind expectedKind,
    AquaLocalRegion expectedRegion,
    Integer bankCount,
    Integer rowCount
);
    return
        tag.kind == expectedKind
        && tag.localDestination.region == expectedRegion
        && scratchpadLocalBank(tag) < fromInteger(bankCount)
        && scratchpadLocalRow(tag) < fromInteger(rowCount);
endfunction

interface ScratchpadResponseStagerIfc#(
    numeric type arrayDim,
    numeric type spadBanks,
    numeric type spadRows,
    numeric type activationWidth,
    numeric type weightWidth
);
    method Bool activationResponseReady(
        ActivationMemoryResponse#(arrayDim, activationWidth) response
    );
    method Action putActivationResponse(
        ActivationMemoryResponse#(arrayDim, activationWidth) response
    );
    method Bool queuedActivationResponseReady(
        ActivationMemoryResponse#(arrayDim, activationWidth) response
    );
    method Action putQueuedActivationResponse(
        ActivationMemoryResponse#(arrayDim, activationWidth) response
    );
    method Bool weightResponseReady(
        WeightMemoryResponse#(arrayDim, weightWidth) response
    );
    method Action putWeightResponse(
        WeightMemoryResponse#(arrayDim, weightWidth) response
    );
    method Bool queuedWeightResponseReady(
        WeightMemoryResponse#(arrayDim, weightWidth) response
    );
    method Action putQueuedWeightResponse(
        WeightMemoryResponse#(arrayDim, weightWidth) response
    );
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
endinterface

module mkScratchpadResponseStager#(
    LoadControllerIfc#(arrayDim, spadBanks, metaEntries) load
)(ScratchpadResponseStagerIfc#(
    arrayDim,
    spadBanks,
    spadRows,
    activationWidth,
    weightWidth
)) provisos (
    Add#(spadBankPadding, TLog#(spadBanks), 32),
    Add#(spadRowPadding, TLog#(TAdd#(spadRows, 1)), 32)
);
    BankedScratchpadIfc#(
        spadBanks,
        spadRows,
        arrayDim,
        Int#(activationWidth)
    ) activations <- mkBankedScratchpad;
    BankedScratchpadIfc#(
        spadBanks,
        spadRows,
        arrayDim,
        Bit#(weightWidth)
    ) weights <- mkBankedScratchpad;

    method Bool activationResponseReady(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Int#(activationWidth))
        ) response
    );
        return load.activationResponseReady(response.tag)
            && validScratchpadResponse(
                response.tag,
                MemoryActivation,
                LocalActivation,
                valueOf(spadBanks),
                valueOf(spadRows)
            );
    endmethod
    method Action putActivationResponse(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Int#(activationWidth))
        ) response
    );
        UInt#(32) bank = scratchpadLocalBank(response.tag);
        UInt#(32) row = scratchpadLocalRow(response.tag);
        UInt#(TLog#(spadBanks)) bankIndex = truncate(bank);
        ScratchpadRowAddr#(spadRows) rowAddress = truncate(pack(row));
        Bool valid = load.activationResponseReady(response.tag)
            && validScratchpadResponse(
                response.tag,
                MemoryActivation,
                LocalActivation,
                valueOf(spadBanks),
                valueOf(spadRows)
            );
        dynamicAssert(valid, "activation response is not outstanding");
        if (valid) begin
            activations.banks[bankIndex].write(
                rowAddress,
                response.payload.mask,
                response.payload.data
            );
            load.completeActivation(response.tag);
        end
    endmethod
    method Bool queuedActivationResponseReady(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Int#(activationWidth))
        ) response
    );
        return load.queuedActivationResponseReady(response.tag)
            && validScratchpadResponse(
                response.tag,
                MemoryActivation,
                LocalActivation,
                valueOf(spadBanks),
                valueOf(spadRows)
            );
    endmethod
    method Action putQueuedActivationResponse(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Int#(activationWidth))
        ) response
    );
        UInt#(32) bank = scratchpadLocalBank(response.tag);
        UInt#(32) row = scratchpadLocalRow(response.tag);
        UInt#(TLog#(spadBanks)) bankIndex = truncate(bank);
        ScratchpadRowAddr#(spadRows) rowAddress = truncate(pack(row));
        Bool valid = load.queuedActivationResponseReady(response.tag)
            && validScratchpadResponse(
                response.tag,
                MemoryActivation,
                LocalActivation,
                valueOf(spadBanks),
                valueOf(spadRows)
            );
        dynamicAssert(valid, "queued activation response mismatch");
        if (valid) begin
            activations.banks[bankIndex].write(
                rowAddress,
                response.payload.mask,
                response.payload.data
            );
            load.completeQueuedActivation(response.tag);
        end
    endmethod

    method Bool weightResponseReady(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Bit#(weightWidth))
        ) response
    );
        return load.weightResponseReady(response.tag)
            && validScratchpadResponse(
                response.tag,
                MemoryWeightCode,
                LocalWeight,
                valueOf(spadBanks),
                valueOf(spadRows)
            );
    endmethod
    method Action putWeightResponse(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Bit#(weightWidth))
        ) response
    );
        UInt#(32) bank = scratchpadLocalBank(response.tag);
        UInt#(32) row = scratchpadLocalRow(response.tag);
        UInt#(TLog#(spadBanks)) bankIndex = truncate(bank);
        ScratchpadRowAddr#(spadRows) rowAddress = truncate(pack(row));
        Bool valid = load.weightResponseReady(response.tag)
            && validScratchpadResponse(
                response.tag,
                MemoryWeightCode,
                LocalWeight,
                valueOf(spadBanks),
                valueOf(spadRows)
            );
        dynamicAssert(valid, "weight response is not outstanding");
        if (valid) begin
            weights.banks[bankIndex].write(
                rowAddress,
                response.payload.mask,
                response.payload.data
            );
            load.completeWeight(response.tag);
        end
    endmethod
    method Bool queuedWeightResponseReady(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Bit#(weightWidth))
        ) response
    );
        return load.queuedWeightResponseReady(response.tag)
            && validScratchpadResponse(
                response.tag,
                MemoryWeightCode,
                LocalWeight,
                valueOf(spadBanks),
                valueOf(spadRows)
            );
    endmethod
    method Action putQueuedWeightResponse(
        AquaMemoryReadResponse#(
            ScratchpadRowPayload#(arrayDim, Bit#(weightWidth))
        ) response
    );
        UInt#(32) bank = scratchpadLocalBank(response.tag);
        UInt#(32) row = scratchpadLocalRow(response.tag);
        UInt#(TLog#(spadBanks)) bankIndex = truncate(bank);
        ScratchpadRowAddr#(spadRows) rowAddress = truncate(pack(row));
        Bool valid = load.queuedWeightResponseReady(response.tag)
            && validScratchpadResponse(
                response.tag,
                MemoryWeightCode,
                LocalWeight,
                valueOf(spadBanks),
                valueOf(spadRows)
            );
        dynamicAssert(valid, "queued weight response mismatch");
        if (valid) begin
            weights.banks[bankIndex].write(
                rowAddress,
                response.payload.mask,
                response.payload.data
            );
            load.completeQueuedWeight(response.tag);
        end
    endmethod

    interface activationBanks = activations.banks;
    interface weightBanks = weights.banks;
endmodule

endpackage
