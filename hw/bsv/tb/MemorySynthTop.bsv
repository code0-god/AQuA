package MemorySynthTop;

import AccumulatorMem::*;
import Scratchpad::*;
import Vector::*;

(* synthesize *)
module mkMemorySynthTop(Empty);
    ScratchpadBankIfc#(8, 4, Int#(8)) scratchpad <- mkScratchpadBank;
    AccumulatorMemIfc#(2, 8, 32) accumulator <- mkAccumulatorMem;
    Reg#(Bool) initialized <- mkReg(False);

    rule initialize(!initialized && scratchpad.writeReady && accumulator.writeReady);
        scratchpad.write(0, replicate(True), replicate(0));
        accumulator.write(0, 0, False, 0);
        initialized <= True;
    endrule
endmodule

endpackage
