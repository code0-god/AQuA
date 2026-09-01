package TbMatmulInvalidDescriptor;

import AquaTypes::*;
import AquaWorkTypes::*;
import MatmulScheduler::*;

(* synthesize *)
module mkTbMatmulInvalidDescriptor(Empty);
    MatmulSchedulerIfc#(16) dut <- mkMatmulScheduler;

    rule start(dut.startReady);
        dut.start(AquaMatmulDescriptor {
            jobId: 1,
            mode: AsyncStripes,
            m: 0,
            n: 16,
            k: 32,
            stripeRows: 16,
            macroNTileColumns: 16,
            activationTensor: 1,
            weightTensor: 2,
            outputTensor: 3,
            jobContext: 4
        });
    endrule
endmodule

endpackage
