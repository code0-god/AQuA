package MemoryMaxDepthSynthTop;

import AccumulatorMem::*;
import StoreController::*;

(* synthesize *)
module mkMemoryMaxDepthSynthTop(StoreControllerIfc#(16, 16, 65536, 32));
    AccumulatorMemIfc#(16, 65536, 32) accumulator <- mkAccumulatorMem;
    let store <- mkStoreController(accumulator);
    return store;
endmodule

endpackage
