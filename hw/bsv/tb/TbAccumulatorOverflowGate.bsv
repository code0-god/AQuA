package TbAccumulatorOverflowGate;

import AccumulatorMem::*;

(* synthesize *)
module mkTbAccumulatorOverflowGate(Empty);
    AccumulatorMemIfc#(1, 1, 8) dut <- mkAccumulatorMem;
    Reg#(UInt#(3)) step <- mkReg(0);

    rule initialize(step == 0 && dut.writeReady);
        dut.write(0, 0, False, 127);
        step <= 1;
    endrule

    rule finishInitialize(step == 1 && dut.writeCompleteValid);
        dut.consumeWriteComplete;
        step <= 2;
    endrule

    rule attemptOverflow(step == 2 && dut.writeReady);
        dut.write(0, 0, True, 1);
        step <= 3;
    endrule

    rule verifyRejected(
        step == 3
        && dut.writeReady
        && dut.readReady
    );
        dut.requestRead(0, 0);
        step <= 4;
    endrule

    rule failPending(
        step == 3
        && !dut.writeReady
    );
        $display("FAIL accumulator overflow entered pending state");
        $finish(1);
    endrule

    rule verifyPreserved(step == 4 && dut.readValid);
        if (dut.readResponse.value == 127) begin
            $display("PASS mkTbAccumulatorOverflowGate");
            $finish(0);
        end
        else begin
            $display("FAIL accumulator overflow changed stored value");
            $finish(1);
        end
    endrule
endmodule

endpackage
