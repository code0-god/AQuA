package SchedulerSynthTop;

import MatmulScheduler::*;
import WorkScheduler::*;

(* synthesize *)
module mkSchedulerSynthTop(Empty);
    MatmulSchedulerIfc#(16) matmul <- mkMatmulScheduler;
    WorkSchedulerIfc#(16) work <- mkWorkScheduler;
endmodule

endpackage
