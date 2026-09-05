package MemorySubsystemSynthTop;

import AquaMemorySubsystem::*;
import AquaMemoryProtocol::*;
import AccumulatorMem::*;

// Expose runtime methods; local scratchpad/HP1 inspection is not this RTL gate.
interface MemorySubsystemRuntimeIfc;
    method Bool loadReady;
    method Action scheduleLoad(ProviderLoadWork#(16) work);
    interface ReadPortIfc#(ActivationMemoryResponse#(16, 8)) activationPort;
    interface ReadPortIfc#(WeightMemoryResponse#(16, 8)) weightPort;
    interface ReadPortIfc#(BlockShiftMemoryResponse#(16, 5)) blockShiftPort;
    interface ReadPortIfc#(RowScaleMemoryResponse#(16, 4)) rowShiftPort;
    method Bool loadCompletionValid;
    method LoadCompletion loadCompletion;
    method Action consumeLoadCompletion;
    method Bool storeReady;
    method Action scheduleStore(StoreWork#(16) work);
    interface WritePortIfc#(32) outputPort;
    method Bool storeCompletionValid;
    method StoreCompletion storeCompletion;
    method Action consumeStoreCompletion;
    interface AccumulatorMemIfc#(16, 12, 32) accumulator;
endinterface

(* synthesize *)
module mkMemorySubsystemSynthTop(MemorySubsystemRuntimeIfc);
    AquaMemorySubsystemIfc#(
        16,
        2, 16,
        4, 32,
        24, 12,
        8, 8,
        5, 4,
        16, 12, 32
    ) subsystem <- mkAquaMemorySubsystem;
    method loadReady = subsystem.loadReady;
    method scheduleLoad(work) = subsystem.scheduleLoad(work);
    interface activationPort = subsystem.activationPort;
    interface weightPort = subsystem.weightPort;
    interface blockShiftPort = subsystem.blockShiftPort;
    interface rowShiftPort = subsystem.rowShiftPort;
    method loadCompletionValid = subsystem.loadCompletionValid;
    method loadCompletion = subsystem.loadCompletion;
    method consumeLoadCompletion = subsystem.consumeLoadCompletion;
    method storeReady = subsystem.storeReady;
    method scheduleStore(work) = subsystem.scheduleStore(work);
    interface outputPort = subsystem.outputPort;
    method storeCompletionValid = subsystem.storeCompletionValid;
    method storeCompletion = subsystem.storeCompletion;
    method consumeStoreCompletion = subsystem.consumeStoreCompletion;
    interface accumulator = subsystem.accumulator;
endmodule

endpackage
