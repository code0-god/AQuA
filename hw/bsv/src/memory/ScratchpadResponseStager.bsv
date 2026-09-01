package ScratchpadResponseStager;

import ActivationSpad::*;
import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryResponseValidation::*;
import AquaMemoryTypes::*;
import LoadControllerTypes::*;
import ScratchpadBank::*;
import ScratchpadResponseStagerTypes::*;
import Vector::*;
import WeightSpad::*;

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
    ActivationSpadIfc#(
        spadBanks,
        spadRows,
        arrayDim,
        Int#(activationWidth)
    ) activations <- mkActivationSpad;
    WeightSpadIfc#(
        spadBanks,
        spadRows,
        arrayDim,
        Bit#(weightWidth)
    ) weights <- mkWeightSpad;

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
        UInt#(32) bank = localBank(response.tag);
        UInt#(32) row = localRow(response.tag);
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
        UInt#(32) bank = localBank(response.tag);
        UInt#(32) row = localRow(response.tag);
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
        UInt#(32) bank = localBank(response.tag);
        UInt#(32) row = localRow(response.tag);
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
        UInt#(32) bank = localBank(response.tag);
        UInt#(32) row = localRow(response.tag);
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
