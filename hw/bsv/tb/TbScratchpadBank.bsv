package TbScratchpadBank;

import Assert::*;
import Vector::*;
import ScratchpadBank::*;

function Vector#(4, Int#(8)) firstRow;
    Vector#(4, Int#(8)) value = replicate(0);
    value[0] = 1;
    value[1] = 2;
    value[2] = 3;
    value[3] = 4;
    return value;
endfunction

function Vector#(4, Int#(8)) secondRow;
    Vector#(4, Int#(8)) value = replicate(0);
    value[0] = 9;
    value[1] = 8;
    value[2] = 7;
    value[3] = 6;
    return value;
endfunction

(* synthesize *)
module mkTbScratchpadBank(Empty);
    ScratchpadBankIfc#(8, 4, Int#(8)) dut <- mkScratchpadBank;
    Reg#(UInt#(8)) step <- mkReg(0);

    rule writeFull(step == 0 && dut.writeReady);
        dut.write(1, replicate(True), firstRow);
        step <= 1;
    endrule

    rule requestFull(step == 1 && dut.readReady);
        dut.requestRead(1);
        step <= 2;
    endrule

    rule holdResponse(step == 2 && dut.readValid);
        dynamicAssert(dut.readData == firstRow, "full-row read mismatch");
        step <= 3;
    endrule

    rule consumeAndMask(step == 3 && dut.readValid && dut.writeReady);
        dynamicAssert(dut.readData == firstRow, "stalled response changed");
        dut.consumeRead;
        Vector#(4, Bool) mask = replicate(False);
        mask[1] = True;
        mask[3] = True;
        dut.write(1, mask, secondRow);
        step <= 4;
    endrule

    rule requestMasked(step == 4 && dut.readReady);
        dut.requestRead(1);
        step <= 5;
    endrule

    rule checkMasked(step == 5 && dut.readValid);
        Vector#(4, Int#(8)) expected = firstRow;
        expected[1] = secondRow[1];
        expected[3] = secondRow[3];
        dynamicAssert(dut.readData == expected, "masked write mismatch");
        dut.consumeRead;
        step <= 6;
    endrule

    rule requestPriority(step == 6 && dut.readReady);
        dut.requestRead(2);
        step <= 7;
    endrule

    rule writePriority(step == 7 && dut.writeReady);
        dut.write(2, replicate(True), secondRow);
        step <= 8;
    endrule

    rule checkPriority(step == 8 && dut.readValid);
        dynamicAssert(dut.readData == secondRow, "write priority mismatch");
        dut.consumeRead;
        step <= 9;
    endrule

    rule writeLastRow(step == 9 && dut.writeReady);
        dut.write(7, replicate(True), firstRow);
        step <= 10;
    endrule

    rule requestLastRow(step == 10 && dut.readReady);
        dut.requestRead(7);
        step <= 11;
    endrule

    rule checkLastRow(step == 11 && dut.readValid);
        dynamicAssert(dut.readData == firstRow, "last bank-local row mismatch");
        dut.consumeRead;
        $display("PASS mkTbScratchpadBank");
        $finish(0);
    endrule
endmodule

endpackage
