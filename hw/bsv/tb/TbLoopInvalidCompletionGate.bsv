package TbLoopInvalidCompletionGate;

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

function LoadCompletion loadCompletion;
    return LoadCompletion {
        jobId: 1,
        stripeId: 0,
        arrayWorkId: 0,
        fragmentId: 0
    };
endfunction

function ExecuteCompletion executeCompletion;
    return ExecuteCompletion {
        jobId: 1,
        stripeId: 0,
        arrayWorkId: 0,
        fragmentId: 0
    };
endfunction

function StoreCompletion storeCompletion;
    return StoreCompletion {
        jobId: 1,
        stripeId: 0,
        arrayWorkId: 0
    };
endfunction

(* synthesize *)
module mkTbLoopInvalidCompletionGate(Empty);
    AquaLoopMatmulIfc#(16) dut <- mkAquaLoopMatmul;
    Reg#(UInt#(4)) step <- mkReg(0);
    Reg#(UInt#(8)) savedPhase <- mkReg(0);
    Reg#(UInt#(16)) cycles <- mkReg(0);

    rule start(step == 0 && dut.startReady);
        dut.start(descriptor);
        step <= 1;
    endrule

    rule putEarlyLoad(step == 1 && dut.loadWorkValid);
        savedPhase <= dut.debugPhase;
        if (dut.loadCompletionReady(loadCompletion)) begin
            $display("FAIL early load completion reported ready");
            $finish(1);
        end
        step <= 2;
    endrule

    rule verifyEarlyLoad(step == 2);
        if (
            dut.debugPhase == savedPhase
            && dut.loadWorkValid
            && !dut.executeWorkValid
        ) begin
            dut.consumeLoadWork;
            step <= 3;
        end
        else begin
            $display("FAIL early load completion changed state");
            $finish(1);
        end
    endrule

    rule putWrongLoad(step == 3);
        savedPhase <= dut.debugPhase;
        dut.putLoadCompletion(LoadCompletion {
            jobId: 1,
            stripeId: 0,
            arrayWorkId: 0,
            fragmentId: 1
        });
        step <= 4;
    endrule

    rule verifyWrongLoad(step == 4);
        if (
            dut.debugPhase == savedPhase
            && dut.loadCompletionReady(loadCompletion)
            && !dut.executeWorkValid
        ) begin
            dut.putLoadCompletion(loadCompletion);
            step <= 5;
        end
        else begin
            $display("FAIL wrong load completion changed state");
            $finish(1);
        end
    endrule

    rule putDuplicateLoad(
        step == 5 && dut.executeWorkValid
    );
        savedPhase <= dut.debugPhase;
        if (dut.loadCompletionReady(loadCompletion)) begin
            $display("FAIL duplicate load completion reported ready");
            $finish(1);
        end
        step <= 6;
    endrule

    rule verifyDuplicateLoad(step == 6);
        if (
            dut.debugPhase == savedPhase
            && dut.executeWorkValid
        ) begin
            dut.consumeExecuteWork;
            step <= 7;
        end
        else begin
            $display("FAIL duplicate load completion changed state");
            $finish(1);
        end
    endrule

    rule putWrongExecute(step == 7);
        savedPhase <= dut.debugPhase;
        dut.putExecuteCompletion(ExecuteCompletion {
            jobId: 1,
            stripeId: 0,
            arrayWorkId: 1,
            fragmentId: 0
        });
        step <= 8;
    endrule

    rule verifyWrongExecute(step == 8);
        if (
            dut.debugPhase == savedPhase
            && dut.executeCompletionReady(executeCompletion)
            && !dut.storeWorkValid
        ) begin
            dut.putExecuteCompletion(executeCompletion);
            step <= 9;
        end
        else begin
            $display("FAIL wrong execute completion changed state");
            $finish(1);
        end
    endrule

    rule putDuplicateExecute(
        step == 9 && dut.storeWorkValid
    );
        savedPhase <= dut.debugPhase;
        if (dut.executeCompletionReady(executeCompletion)) begin
            $display("FAIL duplicate execute completion reported ready");
            $finish(1);
        end
        step <= 10;
    endrule

    rule verifyDuplicateExecute(step == 10);
        if (
            dut.debugPhase == savedPhase
            && dut.storeWorkValid
        ) begin
            dut.consumeStoreWork;
            step <= 11;
        end
        else begin
            $display("FAIL duplicate execute completion changed state");
            $finish(1);
        end
    endrule

    rule putWrongStore(step == 11);
        savedPhase <= dut.debugPhase;
        dut.putStoreCompletion(StoreCompletion {
            jobId: 1,
            stripeId: 1,
            arrayWorkId: 0
        });
        step <= 12;
    endrule

    rule verifyWrongStore(step == 12);
        if (
            dut.debugPhase == savedPhase
            && dut.storeCompletionReady(storeCompletion)
            && !dut.stripeCompletionValid
        ) begin
            dut.putStoreCompletion(storeCompletion);
            step <= 13;
        end
        else begin
            $display("FAIL wrong store completion changed state");
            $finish(1);
        end
    endrule

    rule consumeCompletion(
        step == 13 && dut.stripeCompletionValid
    );
        dut.consumeStripeCompletion;
        step <= 14;
    endrule

    rule finish(step == 14 && dut.startReady);
        $display("PASS: mkTbLoopInvalidCompletionGate");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 200) begin
            $display(
                "WATCHDOG step=%0d phase=%0d",
                step,
                dut.debugPhase
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
