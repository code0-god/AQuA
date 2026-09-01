package TbAccumulatorOverflow;

import AccumulatorMem::*;

(* synthesize *)
module mkTbAccumulatorOverflow(Empty);
    AccumulatorMemIfc#(1, 2, 8) dut <- mkAccumulatorMem;
    Reg#(UInt#(8)) step <- mkReg(0);

    rule initialize(step == 0 && dut.writeReady);
        dut.write(0, 0, False, 127);
        step <= 1;
    endrule

    rule consumeInitialize(step == 1 && dut.writeCompleteValid);
        dut.consumeWriteComplete;
        step <= 2;
    endrule

    rule overflow(step == 2 && dut.writeReady);
        dut.write(0, 0, True, 1);
        step <= 3;
    endrule
endmodule

endpackage
