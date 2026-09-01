package TbHp1MetaMem;

import Assert::*;
import AquaTypes::*;
import Hp1MetaMem::*;

(* synthesize *)
module mkTbHp1MetaMem(Empty);
    Hp1MetaMemIfc#(8, 4) narrow <- mkHp1MetaMem;
    Hp1MetaMemIfc#(8, 16) wide <- mkHp1MetaMem;
    Reg#(UInt#(8)) step <- mkReg(0);

    rule write(step == 0);
        narrow.writeBlockScale(1, Hp1BlockScale {
            zeroBlock: True,
            leftShift: 0
        });
        narrow.writeRowShift(1, 9);
        wide.writeBlockScale(2, Hp1BlockScale {
            zeroBlock: False,
            leftShift: 1024
        });
        wide.writeRowShift(2, 4096);
        step <= 1;
    endrule

    rule verify(step == 1);
        dynamicAssert(narrow.readBlockScale(1).zeroBlock, "narrow zero flag mismatch");
        dynamicAssert(narrow.readRowShift(1) == 9, "narrow row shift mismatch");
        dynamicAssert(!wide.readBlockScale(2).zeroBlock, "wide zero flag mismatch");
        dynamicAssert(wide.readBlockScale(2).leftShift == 1024, "wide block shift mismatch");
        dynamicAssert(wide.readRowShift(2) == 4096, "wide row shift mismatch");
        $display("PASS mkTbHp1MetaMem");
        $finish(0);
    endrule
endmodule

endpackage
