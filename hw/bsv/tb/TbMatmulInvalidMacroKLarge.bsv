package TbMatmulInvalidMacroKLarge;

import AquaTypes::*;
import AquaWorkTypes::*;
import MatmulScheduler::*;

(* synthesize *)
module mkTbMatmulInvalidMacroKLarge(Empty);
    MatmulSchedulerIfc#(16) dut <- mkMatmulScheduler;

    rule start(dut.startReady);
        dut.start(AquaMatmulDescriptor {
            jobId: 1,
            mode: FullMatrix,
            m: 1,
            n: 1,
            k: 32,
            stripeRows: 1,
            macroNTileColumns: 1,
            macroKTileElements: 33,
            activationTensor: 1,
            weightTensor: 2,
            outputTensor: 3,
            jobContext: 4
        });
    endrule
endmodule

endpackage
