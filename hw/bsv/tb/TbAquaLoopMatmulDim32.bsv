package TbAquaLoopMatmulDim32;

import Assert::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import AquaLoopMatmul::*;

function AquaMatmulDescriptor descriptor;
    return AquaMatmulDescriptor {
        jobId: 32,
        mode: FullMatrix,
        m: 1,
        n: 1,
        k: 32,
        stripeRows: 1,
        macroNTileColumns: 1,
        macroKTileElements: 32,
        activationTensor: 1,
        weightTensor: 2,
        outputTensor: 3,
        jobContext: 4
    };
endfunction

(* synthesize *)
module mkTbAquaLoopMatmulDim32(Empty);
    AquaLoopMatmulIfc#(32) dut <- mkAquaLoopMatmul;
    Reg#(UInt#(4)) step <- mkReg(0);
    Reg#(UInt#(8)) cycles <- mkReg(0);

    rule start(step == 0 && dut.startReady);
        dut.start(descriptor);
        step <= 1;
    endrule

    rule consumeLoad(step == 1 && dut.loadWorkValid);
        let work = dut.loadWork;
        dynamicAssert(work.fragmentKStart == 0, "DIM32 K start");
        dynamicAssert(work.fragmentKCount == 32, "DIM32 K count");
        dynamicAssert(work.arrayWorkId == 0, "DIM32 array work ID");
        dynamicAssert(work.fragmentId == 0, "DIM32 fragment ID");
        dut.consumeLoadWork;
        step <= 2;
    endrule

    rule completeLoad(step == 2);
        dut.putLoadCompletion(LoadCompletion {
            jobId: 32,
            stripeId: 0,
            arrayWorkId: 0,
            fragmentId: 0
        });
        step <= 3;
    endrule

    rule consumeExecute(step == 3 && dut.executeWorkValid);
        let work = dut.executeWork;
        dynamicAssert(work.fragmentKCount == 32, "DIM32 execute count");
        dynamicAssert(!work.accumulate, "DIM32 first accumulation");
        dut.consumeExecuteWork;
        step <= 4;
    endrule

    rule completeExecute(step == 4);
        dut.putExecuteCompletion(ExecuteCompletion {
            jobId: 32,
            stripeId: 0,
            arrayWorkId: 0,
            fragmentId: 0
        });
        step <= 5;
    endrule

    rule consumeStore(step == 5 && dut.storeWorkValid);
        dynamicAssert(dut.storeWork.arrayWorkId == 0, "DIM32 store ID");
        dut.consumeStoreWork;
        step <= 6;
    endrule

    rule completeStore(step == 6);
        dut.putStoreCompletion(StoreCompletion {
            jobId: 32,
            stripeId: 0,
            arrayWorkId: 0
        });
        step <= 7;
    endrule

    rule consumeCompletion(
        step == 7 && dut.stripeCompletionValid
    );
        dut.consumeStripeCompletion;
        step <= 8;
    endrule

    rule finish(step == 8 && dut.startReady);
        $display("PASS: mkTbAquaLoopMatmulDim32");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 100) begin
            $display("WATCHDOG step=%0d phase=%0d", step, dut.debugPhase);
            $finish(1);
        end
    endrule
endmodule

endpackage
