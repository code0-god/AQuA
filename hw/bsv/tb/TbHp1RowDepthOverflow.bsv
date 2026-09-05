package TbHp1RowDepthOverflow;

import Hp1MetaMem::*;
import Vector::*;

(* synthesize *)
module mkTbHp1RowDepthOverflow(Empty);
    Hp1MetaMemIfc#(4, 3, 16, 5, 4) dut <- mkHp1MetaMem;

    rule overflow;
        dut.writeRowShifts(3, replicate(True), replicate(1));
    endrule
endmodule

endpackage
