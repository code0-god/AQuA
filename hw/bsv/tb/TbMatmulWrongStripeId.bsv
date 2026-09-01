package TbMatmulWrongStripeId;

import AquaTypes::*;
import AquaWorkTypes::*;
import MatmulScheduler::*;

(* synthesize *)
module mkTbMatmulWrongStripeId(Empty);
    MatmulSchedulerIfc#(16) dut <- mkMatmulScheduler;
    Reg#(UInt#(2)) step <- mkReg(0);

    rule start(step == 0 && dut.startReady);
        dut.start(AquaMatmulDescriptor {
            jobId: 1,
            mode: AsyncStripes,
            m: 16,
            n: 16,
            k: 32,
            stripeRows: 16,
            macroNTileColumns: 16,
            macroKTileElements: 32,
            activationTensor: 1,
            weightTensor: 2,
            outputTensor: 3,
            jobContext: 4
        });
        step <= 1;
    endrule

    rule publish(step == 1 && dut.publishReady);
        dut.publishStripe(ActivationStripe {
            stripeId: 1,
            rowBegin: 0,
            rowCount: 16,
            activationBase: unpack(0),
            stripeContext: 0
        });
        step <= 2;
    endrule
endmodule

endpackage
