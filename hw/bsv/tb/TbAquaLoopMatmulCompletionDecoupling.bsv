package TbAquaLoopMatmulCompletionDecoupling;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import AquaLoopMatmul::*;

function AquaMatmulDescriptor descriptor;
    return AquaMatmulDescriptor {
        jobId: 88,
        mode: AsyncStripes,
        m: 2,
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

function ActivationStripe stripe(StripeId stripeId);
    return ActivationStripe {
        stripeId: stripeId,
        rowBegin: stripeId,
        rowCount: 1,
        activationBase: AquaLocalAddr {
            region: LocalActivation,
            bank: 0,
            row: 0
        },
        stripeContext: zeroExtend(stripeId)
    };
endfunction

(* synthesize *)
module mkTbAquaLoopMatmulCompletionDecoupling(Empty);
    AquaLoopMatmulIfc#(16) dut <- mkAquaLoopMatmul;
    Reg#(UInt#(4)) step <- mkReg(0);
    Reg#(UInt#(1)) stripeIndex <- mkReg(0);
    Reg#(UInt#(1)) fragmentIndex <- mkReg(0);
    Reg#(UInt#(4)) loadCount <- mkReg(0);
    Reg#(UInt#(4)) executeCount <- mkReg(0);
    Reg#(UInt#(3)) storeCount <- mkReg(0);
    Reg#(UInt#(16)) cycles <- mkReg(0);

    rule start(step == 0 && dut.startReady);
        dut.start(descriptor);
        step <= 1;
    endrule

    rule publishFirst(step == 1 && dut.publishReady);
        dut.publishStripe(stripe(0));
        step <= 2;
    endrule

    rule publishSecond(step == 2 && dut.publishReady);
        dut.publishStripe(stripe(1));
        step <= 3;
    endrule

    rule consumeLoad(step == 3 && dut.loadWorkValid);
        let work = dut.loadWork;
        dynamicAssert(
            work.stripeId == zeroExtend(stripeIndex),
            "decoupled load stripe"
        );
        dynamicAssert(
            work.arrayWorkId == zeroExtend(stripeIndex),
            "decoupled load array work"
        );
        dynamicAssert(
            work.fragmentId == zeroExtend(fragmentIndex),
            "decoupled load fragment"
        );
        dynamicAssert(
            work.fragmentKStart == zeroExtend(fragmentIndex) * 16,
            "decoupled load K start"
        );
        dynamicAssert(work.fragmentKCount == 16, "decoupled load K count");
        if (stripeIndex == 1) begin
            dynamicAssert(
                dut.stripeCompletionValid,
                "stripe one load requires pending completion zero"
            );
        end
        dut.consumeLoadWork;
        loadCount <= loadCount + 1;
        step <= 4;
    endrule

    rule completeLoad(step == 4);
        dut.putLoadCompletion(LoadCompletion {
            jobId: 88,
            stripeId: zeroExtend(stripeIndex),
            arrayWorkId: zeroExtend(stripeIndex),
            fragmentId: zeroExtend(fragmentIndex)
        });
        step <= 5;
    endrule

    rule consumeExecute(step == 5 && dut.executeWorkValid);
        if (stripeIndex == 1) begin
            dynamicAssert(
                dut.stripeCompletionValid,
                "stripe one execute requires pending completion zero"
            );
        end
        dut.consumeExecuteWork;
        executeCount <= executeCount + 1;
        step <= 6;
    endrule

    rule completeExecute(step == 6);
        dut.putExecuteCompletion(ExecuteCompletion {
            jobId: 88,
            stripeId: zeroExtend(stripeIndex),
            arrayWorkId: zeroExtend(stripeIndex),
            fragmentId: zeroExtend(fragmentIndex)
        });
        if (fragmentIndex == 0) begin
            fragmentIndex <= 1;
            step <= 3;
        end
        else begin
            step <= 7;
        end
    endrule

    rule consumeStore(step == 7 && dut.storeWorkValid);
        if (stripeIndex == 1) begin
            dynamicAssert(
                dut.stripeCompletionValid,
                "stripe one store requires pending completion zero"
            );
        end
        dut.consumeStoreWork;
        storeCount <= storeCount + 1;
        step <= 8;
    endrule

    rule completeStore(step == 8);
        dut.putStoreCompletion(StoreCompletion {
            jobId: 88,
            stripeId: zeroExtend(stripeIndex),
            arrayWorkId: zeroExtend(stripeIndex)
        });
        step <= 9;
    endrule

    rule observeQueuedCompletion(
        step == 9 && dut.stripeCompletionValid
    );
        dynamicAssert(
            dut.stripeCompletion.stripeId == 0,
            "completion zero must remain at FIFO front"
        );
        if (stripeIndex == 0) begin
            stripeIndex <= 1;
            fragmentIndex <= 0;
            step <= 3;
        end
        else begin
            dynamicAssert(!dut.startReady, "job restarted before completions");
            step <= 10;
        end
    endrule

    rule consumeCompletionZero(
        step == 10 && dut.stripeCompletionValid
    );
        dynamicAssert(
            dut.stripeCompletion.stripeId == 0,
            "first queued completion order"
        );
        dynamicAssert(!dut.startReady, "job ready before final completion");
        dut.consumeStripeCompletion;
        step <= 11;
    endrule

    rule consumeCompletionOne(
        step == 11 && dut.stripeCompletionValid
    );
        dynamicAssert(
            dut.stripeCompletion.stripeId == 1,
            "second queued completion order"
        );
        dynamicAssert(!dut.startReady, "job ready before completion consume");
        dut.consumeStripeCompletion;
        step <= 12;
    endrule

    rule finish(step == 12 && dut.startReady);
        dynamicAssert(loadCount == 4, "decoupled load count");
        dynamicAssert(executeCount == 4, "decoupled execute count");
        dynamicAssert(storeCount == 2, "decoupled store count");
        $display("PASS: mkTbAquaLoopMatmulCompletionDecoupling");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 300) begin
            $display(
                "WATCHDOG step=%0d phase=%0d stripe=%0d fragment=%0d",
                step,
                dut.debugPhase,
                stripeIndex,
                fragmentIndex
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
