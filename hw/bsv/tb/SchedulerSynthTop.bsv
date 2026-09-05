package SchedulerSynthTop;

import MatmulScheduler::*;

(* synthesize *)
module mkSchedulerSynthTop(MatmulSchedulerIfc#(16));
    MatmulSchedulerIfc#(16) matmul <- mkMatmulScheduler;
    return matmul;
endmodule

endpackage
