package TbAquaLoopMatmulDim64;

import Assert::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import AquaLoopMatmul::*;

function AquaMatmulDescriptor descriptor;
    return AquaMatmulDescriptor {
        jobId: 64,
        mode: FullMatrix,
        m: 1,
        n: 1,
        k: 64,
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
module mkTbAquaLoopMatmulDim64(Empty);
    AquaLoopMatmulIfc#(64) dut <- mkAquaLoopMatmul;
    Reg#(UInt#(4)) step <- mkReg(0);
    Reg#(UInt#(1)) tileIndex <- mkReg(0);
    Reg#(UInt#(8)) cycles <- mkReg(0);

    rule start(step == 0 && dut.startReady);
        dut.start(descriptor);
        step <= 1;
    endrule

    rule consumeLoad(step == 1 && dut.loadWorkValid);
        let work = dut.loadWork;
        MatrixExtent expectedStart = zeroExtend(tileIndex) * 32;
        dynamicAssert(
            work.fragmentKStart == expectedStart,
            "DIM64 K start"
        );
        dynamicAssert(work.fragmentKCount == 32, "DIM64 K count");
        dynamicAssert(
            work.arrayWorkId == zeroExtend(tileIndex),
            "DIM64 array work ID"
        );
        dynamicAssert(work.fragmentId == 0, "DIM64 fragment ID");
        dynamicAssert(!dut.storeWorkValid, "DIM64 early store");
        dut.consumeLoadWork;
        step <= 2;
    endrule

    rule completeLoad(step == 2);
        dut.putLoadCompletion(LoadCompletion {
            jobId: 64,
            stripeId: 0,
            arrayWorkId: zeroExtend(tileIndex),
            fragmentId: 0
        });
        step <= 3;
    endrule

    rule consumeExecute(step == 3 && dut.executeWorkValid);
        let work = dut.executeWork;
        dynamicAssert(
            work.fragmentKStart == zeroExtend(tileIndex) * 32,
            "DIM64 execute start"
        );
        dynamicAssert(work.fragmentKCount == 32, "DIM64 execute count");
        dynamicAssert(
            work.accumulate == (tileIndex == 1),
            "DIM64 accumulation"
        );
        dynamicAssert(!dut.storeWorkValid, "DIM64 execute early store");
        dut.consumeExecuteWork;
        step <= 4;
    endrule

    rule completeExecute(step == 4);
        dut.putExecuteCompletion(ExecuteCompletion {
            jobId: 64,
            stripeId: 0,
            arrayWorkId: zeroExtend(tileIndex),
            fragmentId: 0
        });
        if (tileIndex == 0) begin
            tileIndex <= 1;
            step <= 1;
        end
        else begin
            step <= 5;
        end
    endrule

    rule consumeStore(step == 5 && dut.storeWorkValid);
        dynamicAssert(dut.storeWork.arrayWorkId == 1, "DIM64 store ID");
        dut.consumeStoreWork;
        step <= 6;
    endrule

    rule completeStore(step == 6);
        dut.putStoreCompletion(StoreCompletion {
            jobId: 64,
            stripeId: 0,
            arrayWorkId: 1
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
        $display("PASS: mkTbAquaLoopMatmulDim64");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 150) begin
            $display(
                "WATCHDOG step=%0d phase=%0d tile=%0d",
                step,
                dut.debugPhase,
                tileIndex
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
