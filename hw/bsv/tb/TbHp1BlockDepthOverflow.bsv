package TbHp1BlockDepthOverflow;

import AquaTypes::*;
import Hp1MetaMem::*;
import Vector::*;

(* synthesize *)
module mkTbHp1BlockDepthOverflow(Empty);
    Hp1MetaMemIfc#(3, 4, 16, 5, 4) dut <- mkHp1MetaMem;

    rule overflow;
        dut.writeBlockScales(
            3,
            replicate(True),
            replicate(Hp1BlockScale { zeroBlock: False, leftShift: 1 })
        );
    endrule
endmodule

endpackage
