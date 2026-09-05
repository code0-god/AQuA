package TbAccumulatorMem;

import Assert::*;
import AccumulatorMem::*;

(* synthesize *)
module mkTbAccumulatorMem(Empty);
    AccumulatorMemIfc#(2, 8, 32) dut <- mkAccumulatorMem;
    Reg#(UInt#(8)) step <- mkReg(0);

    rule overwrite(step == 0 && dut.writeReady);
        dut.write(0, 3, False, 10);
        step <= 1;
    endrule

    rule consumeOverwrite(step == 1 && dut.writeCompleteValid);
        dynamicAssert(dut.writeComplete.bank == 0, "overwrite bank mismatch");
        dynamicAssert(dut.writeComplete.row == 3, "overwrite row mismatch");
        dut.consumeWriteComplete;
        step <= 2;
    endrule

    rule accumulateNegative(step == 2 && dut.writeReady);
        dut.write(0, 3, True, -4);
        step <= 3;
    endrule

    rule consumeAccumulate(step == 3 && dut.writeCompleteValid);
        dut.consumeWriteComplete;
        step <= 4;
    endrule

    rule accumulateAgain(step == 4 && dut.writeReady);
        dut.write(0, 3, True, 7);
        step <= 5;
    endrule

    rule consumeAgain(step == 5 && dut.writeCompleteValid);
        dut.consumeWriteComplete;
        step <= 6;
    endrule

    rule writeOtherBank(step == 6 && dut.writeReady);
        dut.write(1, 3, False, -9);
        step <= 7;
    endrule

    rule consumeOtherBank(step == 7 && dut.writeCompleteValid);
        dut.consumeWriteComplete;
        step <= 8;
    endrule

    rule requestFirst(step == 8 && dut.readReady);
        dut.requestRead(0, 3);
        step <= 9;
    endrule

    rule holdFirst(step == 9 && dut.readValid);
        dynamicAssert(dut.readResponse.value == 13, "accumulated value mismatch");
        step <= 10;
    endrule

    rule consumeFirst(step == 10 && dut.readValid);
        dynamicAssert(dut.readResponse.value == 13, "stalled accumulator response changed");
        dut.consumeRead;
        step <= 11;
    endrule

    rule requestSecond(step == 11 && dut.readReady);
        dut.requestRead(1, 3);
        step <= 12;
    endrule

    rule checkSecond(step == 12 && dut.readValid);
        dynamicAssert(dut.readResponse.value == -9, "bank isolation mismatch");
        dut.consumeRead;
        $display("PASS: mkTbAccumulatorMem");
        $finish(0);
    endrule
endmodule

endpackage
