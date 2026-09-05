package TbAquaLoopMatmulAsync;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import AquaLoopMatmul::*;

function AquaMatmulDescriptor descriptor;
    return AquaMatmulDescriptor {
        jobId: 77,
        mode: AsyncStripes,
        m: 2,
        n: 1,
        k: 16,
        stripeRows: 1,
        macroNTileColumns: 1,
        macroKTileElements: 16,
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
module mkTbAquaLoopMatmulAsync(Empty);
    AquaLoopMatmulIfc#(16) dut <- mkAquaLoopMatmul;
    Reg#(UInt#(4)) step <- mkReg(0);
    Reg#(UInt#(1)) stripeIndex <- mkReg(0);
    Reg#(UInt#(8)) cycles <- mkReg(0);

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
            "async load stripe"
        );
        dynamicAssert(
            work.arrayWorkId == zeroExtend(stripeIndex),
            "async load array work"
        );
        dynamicAssert(work.fragmentId == 0, "async load fragment");
        dut.consumeLoadWork;
        step <= 4;
    endrule

    rule completeLoad(step == 4);
        dut.putLoadCompletion(LoadCompletion {
            jobId: 77,
            stripeId: zeroExtend(stripeIndex),
            arrayWorkId: zeroExtend(stripeIndex),
            fragmentId: 0
        });
        step <= 5;
    endrule

    rule consumeExecute(step == 5 && dut.executeWorkValid);
        dynamicAssert(
            dut.executeWork.iStart == zeroExtend(stripeIndex),
            "async execute row"
        );
        dut.consumeExecuteWork;
        step <= 6;
    endrule

    rule completeExecute(step == 6);
        dut.putExecuteCompletion(ExecuteCompletion {
            jobId: 77,
            stripeId: zeroExtend(stripeIndex),
            arrayWorkId: zeroExtend(stripeIndex),
            fragmentId: 0
        });
        step <= 7;
    endrule

    rule consumeStore(step == 7 && dut.storeWorkValid);
        dynamicAssert(
            dut.storeWork.iStart == zeroExtend(stripeIndex),
            "async store row"
        );
        dut.consumeStoreWork;
        step <= 8;
    endrule

    rule completeStore(step == 8);
        dut.putStoreCompletion(StoreCompletion {
            jobId: 77,
            stripeId: zeroExtend(stripeIndex),
            arrayWorkId: zeroExtend(stripeIndex)
        });
        step <= 9;
    endrule

    rule consumeCompletion(
        step == 9 && dut.stripeCompletionValid
    );
        dynamicAssert(
            dut.stripeCompletion.stripeId == zeroExtend(stripeIndex),
            "async completion order"
        );
        dut.consumeStripeCompletion;
        if (stripeIndex == 0) begin
            stripeIndex <= 1;
            step <= 3;
        end
        else begin
            step <= 10;
        end
    endrule

    rule finish(step == 10 && dut.startReady);
        $display("PASS: mkTbAquaLoopMatmulAsync");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 180) begin
            $display(
                "WATCHDOG step=%0d phase=%0d stripe=%0d",
                step,
                dut.debugPhase,
                stripeIndex
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
