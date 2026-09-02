package TbLoopWrongLoadCompletion;

import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import AquaLoopMatmul::*;

function AquaMatmulDescriptor descriptor;
    return AquaMatmulDescriptor {
        jobId: 1,
        mode: FullMatrix,
        m: 1,
        n: 1,
        k: 16,
        stripeRows: 1,
        macroNTileColumns: 1,
        macroKTileElements: 16,
        activationTensor: 2,
        weightTensor: 3,
        outputTensor: 4,
        jobContext: 5
    };
endfunction

(* synthesize *)
module mkTbLoopWrongLoadCompletion(Empty);
    AquaLoopMatmulIfc#(16) dut <- mkAquaLoopMatmul;
    Reg#(UInt#(3)) step <- mkReg(0);

    rule start(step == 0 && dut.startReady);
        dut.start(descriptor);
        step <= 1;
    endrule

    rule consumeLoad(step == 1 && dut.loadWorkValid);
        dut.consumeLoadWork;
        step <= 2;
    endrule

    rule putWrongLoad(step == 2);
        dut.putLoadCompletion(LoadCompletion {
            jobId: 1,
            stripeId: 0,
            arrayWorkId: 0,
            fragmentId: 1
        });
        step <= 3;
    endrule

    rule unexpectedlyAccepted(step == 3);
        $display("wrong load completion unexpectedly accepted");
        $finish(1);
    endrule
endmodule

endpackage
