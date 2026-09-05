package TbAquaLoopMatmul;

import Assert::*;
import AquaLocalAddr::*;
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
        k: 80,
        stripeRows: 1,
        macroNTileColumns: 1,
        macroKTileElements: 32,
        activationTensor: 10,
        weightTensor: 11,
        outputTensor: 12,
        jobContext: 13
    };
endfunction

function ArrayWorkId expectedArrayWorkId(UInt#(3) fragmentIndex);
    ArrayWorkId result = 2;
    if (fragmentIndex < 2) begin
        result = 0;
    end
    else if (fragmentIndex < 4) begin
        result = 1;
    end
    return result;
endfunction

function KFragmentId expectedFragmentId(UInt#(3) fragmentIndex);
    return fragmentIndex == 1 || fragmentIndex == 3 ? 1 : 0;
endfunction

function MatrixExtent expectedKStart(UInt#(3) fragmentIndex);
    return zeroExtend(fragmentIndex) * 16;
endfunction

(* synthesize *)
module mkTbAquaLoopMatmul(Empty);
    AquaLoopMatmulIfc#(16) dut <- mkAquaLoopMatmul;

    Reg#(Bool) started <- mkReg(False);
    Reg#(UInt#(3)) fragmentIndex <- mkReg(0);
    Reg#(UInt#(4)) driverPhase <- mkReg(0);
    Reg#(UInt#(16)) cycles <- mkReg(0);
    Reg#(UInt#(4)) loadCount <- mkReg(0);
    Reg#(UInt#(4)) executeCount <- mkReg(0);
    Reg#(UInt#(4)) storeCount <- mkReg(0);

    rule start(!started && dut.startReady);
        dut.start(descriptor);
        started <= True;
    endrule

    rule consumeLoad(
        started
        && driverPhase == 0
        && dut.loadWorkValid
    );
        let work = dut.loadWork;
        ArrayWorkId expectedWorkId =
            expectedArrayWorkId(fragmentIndex);
        KFragmentId expectedId = expectedFragmentId(fragmentIndex);
        MatrixExtent expectedStart = expectedKStart(fragmentIndex);

        dynamicAssert(work.jobId == 1, "load job ID");
        dynamicAssert(work.stripeId == 0, "load stripe ID");
        dynamicAssert(
            work.arrayWorkId == expectedWorkId,
            "load array work ID"
        );
        dynamicAssert(work.fragmentId == expectedId, "load fragment ID");
        dynamicAssert(work.iStart == 0 && work.iCount == 1, "load I range");
        dynamicAssert(work.jStart == 0 && work.jCount == 1, "load J range");
        dynamicAssert(
            work.fragmentKStart == expectedStart,
            "load K start"
        );
        dynamicAssert(work.fragmentKCount == 16, "load K count");
        dynamicAssert(
            work.fragmentBlockIndex == expectedStart / 32,
            "load block index"
        );
        dynamicAssert(
            work.activationBase.region == LocalActivation,
            "load activation region"
        );
        dynamicAssert(
            work.weightBase.region == LocalWeight,
            "load weight region"
        );
        dynamicAssert(!dut.storeWorkValid, "early store offer");
        dynamicAssert(
            !dut.stripeCompletionValid,
            "early stripe completion"
        );

        dut.consumeLoadWork;
        loadCount <= loadCount + 1;
        driverPhase <= 1;
    endrule

    rule completeLoad(started && driverPhase == 1);
        LoadCompletion completion = LoadCompletion {
            jobId: 1,
            stripeId: 0,
            arrayWorkId: expectedArrayWorkId(fragmentIndex),
            fragmentId: expectedFragmentId(fragmentIndex)
        };
        dynamicAssert(
            dut.loadCompletionReady(completion),
            "load completion not ready"
        );
        dut.putLoadCompletion(completion);
        driverPhase <= 2;
    endrule

    rule consumeExecute(
        started
        && driverPhase == 2
        && dut.executeWorkValid
    );
        let work = dut.executeWork;
        MatrixExtent expectedStart = expectedKStart(fragmentIndex);

        dynamicAssert(
            work.arrayWorkId == expectedArrayWorkId(fragmentIndex),
            "execute array work ID"
        );
        dynamicAssert(
            work.fragmentId == expectedFragmentId(fragmentIndex),
            "execute fragment ID"
        );
        dynamicAssert(
            work.fragmentKStart == expectedStart,
            "execute K start"
        );
        dynamicAssert(work.fragmentKCount == 16, "execute K count");
        dynamicAssert(
            work.fragmentEndsBlock
            == (fragmentIndex == 1 || fragmentIndex == 3),
            "execute block ending"
        );
        dynamicAssert(
            work.accumulate == (fragmentIndex != 0),
            "execute accumulate"
        );
        dynamicAssert(
            work.accumulatorBase.region == LocalAccumulator
            && work.accumulatorBase.bank == 0
            && work.accumulatorBase.row == 0,
            "execute accumulator base"
        );
        dynamicAssert(!dut.storeWorkValid, "execute early store");

        dut.consumeExecuteWork;
        executeCount <= executeCount + 1;
        driverPhase <= 3;
    endrule

    rule completeExecute(started && driverPhase == 3);
        ExecuteCompletion completion = ExecuteCompletion {
            jobId: 1,
            stripeId: 0,
            arrayWorkId: expectedArrayWorkId(fragmentIndex),
            fragmentId: expectedFragmentId(fragmentIndex)
        };
        dynamicAssert(
            dut.executeCompletionReady(completion),
            "execute completion not ready"
        );
        dut.putExecuteCompletion(completion);
        if (fragmentIndex == 4) begin
            driverPhase <= 4;
        end
        else begin
            fragmentIndex <= fragmentIndex + 1;
            driverPhase <= 0;
        end
    endrule

    rule consumeStore(
        started
        && driverPhase == 4
        && dut.storeWorkValid
    );
        let work = dut.storeWork;
        dynamicAssert(work.jobId == 1, "store job ID");
        dynamicAssert(work.stripeId == 0, "store stripe ID");
        dynamicAssert(work.arrayWorkId == 2, "store array work ID");
        dynamicAssert(work.outputTensor == 12, "store output tensor");
        dynamicAssert(work.iStart == 0 && work.iCount == 1, "store I range");
        dynamicAssert(work.jStart == 0 && work.jCount == 1, "store J range");
        dynamicAssert(
            !dut.stripeCompletionValid,
            "completion before store acknowledgement"
        );

        dut.consumeStoreWork;
        storeCount <= storeCount + 1;
        driverPhase <= 5;
    endrule

    rule completeStore(started && driverPhase == 5);
        StoreCompletion completion = StoreCompletion {
            jobId: 1,
            stripeId: 0,
            arrayWorkId: 2
        };
        dynamicAssert(
            dut.storeCompletionReady(completion),
            "store completion not ready"
        );
        dynamicAssert(
            !dut.stripeCompletionValid,
            "completion before store response"
        );
        dut.putStoreCompletion(completion);
        driverPhase <= 6;
    endrule

    rule consumeStripeCompletion(
        started
        && driverPhase == 6
        && dut.stripeCompletionValid
    );
        dynamicAssert(
            dut.stripeCompletion.jobId == 1,
            "stripe completion job"
        );
        dynamicAssert(
            dut.stripeCompletion.stripeId == 0,
            "stripe completion stripe"
        );
        dut.consumeStripeCompletion;
        driverPhase <= 7;
    endrule

    rule finish(
        started
        && driverPhase == 7
        && dut.startReady
    );
        dynamicAssert(loadCount == 5, "load count");
        dynamicAssert(executeCount == 5, "execute count");
        dynamicAssert(storeCount == 1, "store count");
        $display("PASS: mkTbAquaLoopMatmul");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 300) begin
            $display(
                "WATCHDOG phase=%0d driver=%0d fragment=%0d",
                dut.debugPhase,
                driverPhase,
                fragmentIndex
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
