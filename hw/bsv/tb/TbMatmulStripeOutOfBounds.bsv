package TbMatmulStripeOutOfBounds;

import AquaTypes::*;
import AquaWorkTypes::*;
import MatmulScheduler::*;

(* synthesize *)
module mkTbMatmulStripeOutOfBounds(Empty);
    MatmulSchedulerIfc#(16) dut <- mkMatmulScheduler;
    Reg#(UInt#(8)) step <- mkReg(0);

    rule start(step == 0 && dut.startReady);
        dut.start(AquaMatmulDescriptor {
            jobId: 1, mode: AsyncStripes, m: 16, n: 16, k: 32,
            stripeRows: 8, macroNTileColumns: 16,
            activationTensor: 1, weightTensor: 2, outputTensor: 3,
            jobContext: 0
        });
        step <= 1;
    endrule

    rule publishOutOfBounds(step == 1 && dut.publishReady);
        dut.publishStripe(ActivationStripe {
            stripeId: 0, rowBegin: 0, rowCount: 17,
            activationBase: unpack(0), stripeContext: 0
        });
        step <= 2;
    endrule
endmodule

endpackage
