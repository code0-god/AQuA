package ScratchpadResponseStagerTypes;

import AquaMemoryTypes::*;
import ScratchpadBank::*;
import Vector::*;

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

endpackage
