package LoopMatmulSynthTop;

import AquaLoopMatmul::*;

(* synthesize *)
module mkLoopMatmulSynthTop(AquaLoopMatmulIfc#(16));
    AquaLoopMatmulIfc#(16) loop <- mkAquaLoopMatmul;
    return loop;
endmodule

endpackage
