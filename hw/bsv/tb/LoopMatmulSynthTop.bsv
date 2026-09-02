package LoopMatmulSynthTop;

import AquaLoopMatmul::*;

(* synthesize *)
module mkLoopMatmulSynthTop(Empty);
    AquaLoopMatmulIfc#(16) loop <- mkAquaLoopMatmul;
endmodule

endpackage
