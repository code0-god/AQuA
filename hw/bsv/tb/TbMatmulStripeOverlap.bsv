package TbMatmulStripeOverlap;

import AquaTypes::*;
import AquaWorkTypes::*;
import MatmulScheduler::*;

(* synthesize *)
module mkTbMatmulStripeOverlap(Empty);
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

    rule publishFirst(step == 1 && dut.publishReady);
        dut.publishStripe(ActivationStripe {
            stripeId: 0, rowBegin: 0, rowCount: 8,
            activationBase: unpack(0), stripeContext: 0
        });
        step <= 2;
    endrule

    rule publishOverlap(step == 2 && dut.publishReady);
        dut.publishStripe(ActivationStripe {
            stripeId: 1, rowBegin: 4, rowCount: 8,
            activationBase: unpack(0), stripeContext: 0
        });
        step <= 3;
    endrule
endmodule

endpackage
