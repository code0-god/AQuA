package TbHp1MetaMem;

import Assert::*;
import AquaTypes::*;
import Hp1MetaMem::*;
import Vector::*;

function Hp1BlockScale#(4) leftShift(UInt#(4) shift);
    return Hp1BlockScale { zeroBlock: False, leftShift: shift };
endfunction

function Hp1BlockScale#(4) zeroBlock;
    return Hp1BlockScale { zeroBlock: True, leftShift: 0 };
endfunction

function Vector#(16, Bool) firstThreeMask;
    Vector#(16, Bool) mask = replicate(False);
    mask[0] = True;
    mask[1] = True;
    mask[2] = True;
    return mask;
endfunction

function Vector#(16, Hp1BlockScale#(4)) blockScales;
    Vector#(16, Hp1BlockScale#(4)) values = replicate(leftShift(9));
    values[0] = leftShift(1);
    values[1] = leftShift(3);
    values[2] = zeroBlock;
    return values;
endfunction

function Vector#(16, UInt#(4)) rowShifts;
    Vector#(16, UInt#(4)) values = replicate(15);
    values[0] = 5;
    values[1] = 8;
    values[2] = 11;
    return values;
endfunction

(* synthesize *)
module mkTbHp1MetaMem(Empty);
    Hp1MetaMemIfc#(8, 16, 4) dut <- mkHp1MetaMem;
    Reg#(UInt#(2)) step <- mkReg(0);

    rule initialize(step == 0);
        dut.writeBlockScales(1, replicate(True), replicate(leftShift(9)));
        dut.writeRowShifts(1, replicate(True), replicate(15));
        step <= 1;
    endrule

    rule writePartial(step == 1);
        dut.writeBlockScales(1, firstThreeMask, blockScales);
        dut.writeRowShifts(1, firstThreeMask, rowShifts);
        step <= 2;
    endrule

    rule verify(step == 2);
        let blocks = dut.readBlockScales(1);
        let rows = dut.readRowShifts(1);

        dynamicAssert(!blocks[0].zeroBlock && blocks[0].leftShift == 1,
                      "HP1 block lane zero mismatch");
        dynamicAssert(!blocks[1].zeroBlock && blocks[1].leftShift == 3,
                      "HP1 block lane one mismatch");
        dynamicAssert(blocks[2].zeroBlock,
                      "HP1 block lane two zero-block mismatch");
        dynamicAssert(rows[0] == 5, "HP1 row lane zero mismatch");
        dynamicAssert(rows[1] == 8, "HP1 row lane one mismatch");
        dynamicAssert(rows[2] == 11, "HP1 row lane two mismatch");

        dynamicAssert(!blocks[3].zeroBlock && blocks[3].leftShift == 9,
                      "masked block lane changed");
        dynamicAssert(!blocks[15].zeroBlock && blocks[15].leftShift == 9,
                      "last masked block lane changed");
        dynamicAssert(rows[3] == 15, "masked row lane changed");
        dynamicAssert(rows[15] == 15, "last masked row lane changed");

        $display("PASS mkTbHp1MetaMem");
        $finish(0);
    endrule
endmodule

endpackage
