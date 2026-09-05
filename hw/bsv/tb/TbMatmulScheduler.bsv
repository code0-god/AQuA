package TbMatmulScheduler;

import Assert::*;
import AquaLocalAddr::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import MatmulScheduler::*;

function AquaMatmulDescriptor descriptor(
    MatmulJobId jobId,
    MatmulMode mode,
    MatrixExtent m,
    MatrixExtent n,
    MatrixExtent k,
    MatrixExtent stripeRows
);
    return descriptorWithMacroN(
        jobId,
        mode,
        m,
        n,
        k,
        stripeRows,
        n
    );
endfunction

function AquaMatmulDescriptor descriptorWithMacroN(
    MatmulJobId jobId,
    MatmulMode mode,
    MatrixExtent m,
    MatrixExtent n,
    MatrixExtent k,
    MatrixExtent stripeRows,
    MatrixExtent macroNTileColumns
);
    return AquaMatmulDescriptor {
        jobId: jobId,
        mode: mode,
        m: m,
        n: n,
        k: k,
        stripeRows: stripeRows,
        macroNTileColumns: macroNTileColumns,
        macroKTileElements: k,
        activationTensor: 1,
        weightTensor: 2,
        outputTensor: 3,
        jobContext: 99
    };
endfunction

function ActivationStripe stripe(
    StripeId stripeId,
    MatrixExtent rowBegin,
    MatrixExtent rowCount
);
    return ActivationStripe {
        stripeId: stripeId,
        rowBegin: rowBegin,
        rowCount: rowCount,
        activationBase: AquaLocalAddr {
            region: LocalActivation,
            bank: 0,
            row: 0
        },
        stripeContext: zeroExtend(stripeId)
    };
endfunction

(* synthesize *)
module mkTbMatmulScheduler(Empty);
    MatmulSchedulerIfc#(16) full <- mkMatmulScheduler;
    MatmulSchedulerIfc#(16) async <- mkMatmulScheduler;
    MatmulSchedulerIfc#(16) macroN <- mkMatmulScheduler;
    MatmulSchedulerIfc#(16) macroNEdge <- mkMatmulScheduler;
    Reg#(UInt#(8)) fullStep <- mkReg(0);
    Reg#(UInt#(8)) asyncStep <- mkReg(0);
    Reg#(UInt#(8)) macroNStep <- mkReg(0);
    Reg#(UInt#(8)) macroNEdgeStep <- mkReg(0);
    Reg#(UInt#(16)) cycles <- mkReg(0);
    Reg#(Bool) fullDone <- mkReg(False);
    Reg#(Bool) asyncDone <- mkReg(False);
    Reg#(Bool) macroNDone <- mkReg(False);
    Reg#(Bool) macroNEdgeDone <- mkReg(False);

    rule startFull(fullStep == 0 && full.startReady);
        full.start(descriptor(1, FullMatrix, 40, 20, 48, 20));
        fullStep <= 1;
    endrule

    rule fullWork00(fullStep == 1 && full.workValid);
        let work = full.currentWork;
        dynamicAssert(work.iStart == 0, "full first I");
        dynamicAssert(work.jStart == 0, "full first J");
        dynamicAssert(work.iCount == 16, "full first I count");
        dynamicAssert(work.jCount == 16, "full first J count");
        dynamicAssert(work.kTileStart == 0, "full K start");
        dynamicAssert(work.kTileCount == 48, "full K count");
        dynamicAssert(full.lookaheadValid, "full lookahead missing");
        dynamicAssert(full.lookaheadStripe.stripeId == 1, "full lookahead ID");
        full.completeWork;
        fullStep <= 2;
    endrule

    rule fullWork01(fullStep == 2 && full.workValid);
        let work = full.currentWork;
        dynamicAssert(work.iStart == 0, "J must advance before I");
        dynamicAssert(work.jStart == 16, "second J start");
        dynamicAssert(work.jCount == 4, "partial J count");
        full.completeWork;
        fullStep <= 3;
    endrule

    rule fullWork10(fullStep == 3 && full.workValid);
        let work = full.currentWork;
        dynamicAssert(work.iStart == 16, "second I start");
        dynamicAssert(work.jStart == 0, "J reset after I advance");
        dynamicAssert(work.iCount == 4, "partial I count");
        full.completeWork;
        fullStep <= 4;
    endrule

    rule fullWork11(fullStep == 4 && full.workValid);
        let work = full.currentWork;
        dynamicAssert(work.iStart == 16, "final I start");
        dynamicAssert(work.jStart == 16, "final J start");
        dynamicAssert(work.iCount == 4, "final I count");
        dynamicAssert(work.jCount == 4, "final J count");
        full.completeWork;
        fullStep <= 5;
    endrule

    rule fullCompletion0(fullStep == 5 && full.completionValid);
        dynamicAssert(full.completion.stripeId == 0, "first completion order");
        full.consumeCompletion;
        fullStep <= 6;
    endrule

    rule consumeSecondStripe(fullStep >= 6 && fullStep < 10 && full.workValid);
        let work = full.currentWork;
        dynamicAssert(work.stripeId == 1, "promoted stripe ID");
        dynamicAssert(work.iStart >= 20, "promoted stripe rows");
        full.completeWork;
        fullStep <= fullStep + 1;
    endrule

    rule fullCompletion1(fullStep == 10 && full.completionValid);
        dynamicAssert(full.completion.stripeId == 1, "second completion order");
        full.consumeCompletion;
        fullStep <= 11;
    endrule

    rule startSmall(fullStep == 11 && full.startReady);
        full.start(descriptor(2, FullMatrix, 8, 7, 16, 8));
        fullStep <= 12;
    endrule

    rule checkSmall(fullStep == 12 && full.workValid);
        let work = full.currentWork;
        dynamicAssert(work.iCount == 8, "small I count");
        dynamicAssert(work.jCount == 7, "small J count");
        full.completeWork;
        fullStep <= 13;
    endrule

    rule finishSmall(fullStep == 13 && full.completionValid);
        full.consumeCompletion;
        fullDone <= True;
        fullStep <= 14;
    endrule

    rule startAsync(asyncStep == 0 && async.startReady);
        async.start(descriptor(7, AsyncStripes, 24, 8, 32, 16));
        asyncStep <= 1;
    endrule

    rule publishAsync0(asyncStep == 1 && async.publishReady);
        async.publishStripe(stripe(0, 0, 16));
        asyncStep <= 2;
    endrule

    rule publishAsync1(asyncStep == 2 && async.publishReady);
        async.publishStripe(stripe(1, 16, 8));
        asyncStep <= 3;
    endrule

    rule checkAsync0(asyncStep == 3 && async.workValid);
        dynamicAssert(async.currentWork.stripeId == 0, "async first stripe");
        dynamicAssert(async.lookaheadValid, "async lookahead missing");
        dynamicAssert(async.lookaheadStripe.stripeId == 1, "async lookahead ID");
        async.completeWork;
        asyncStep <= 4;
    endrule

    rule completeAsync0(asyncStep == 4 && async.completionValid);
        dynamicAssert(async.completion.stripeId == 0, "async first completion");
        async.consumeCompletion;
        asyncStep <= 5;
    endrule

    rule checkAsync1(asyncStep == 5 && async.workValid);
        dynamicAssert(async.currentWork.stripeId == 1, "async second stripe");
        dynamicAssert(async.currentWork.iCount == 8, "async partial stripe");
        async.completeWork;
        asyncStep <= 6;
    endrule

    rule completeAsync1(asyncStep == 6 && async.completionValid);
        dynamicAssert(async.completion.stripeId == 1, "async second completion");
        async.consumeCompletion;
        asyncDone <= True;
        asyncStep <= 7;
    endrule

    rule startMacroN(macroNStep == 0 && macroN.startReady);
        macroN.start(
            descriptorWithMacroN(3, FullMatrix, 16, 40, 32, 16, 18)
        );
        macroNStep <= 1;
    endrule

    rule macroNWork0(macroNStep == 1 && macroN.workValid);
        let work = macroN.currentWork;
        dynamicAssert(work.iStart == 0, "macro N first I");
        dynamicAssert(work.jStart == 0, "macro N first J");
        dynamicAssert(work.jCount == 16, "macro N first J count");
        macroN.completeWork;
        macroNStep <= 2;
    endrule

    rule macroNWork1(macroNStep == 2 && macroN.workValid);
        let work = macroN.currentWork;
        dynamicAssert(work.iStart == 0, "macro N first tile I");
        dynamicAssert(work.jStart == 16, "macro N first tile edge J");
        dynamicAssert(work.jCount == 2, "macro N first tile edge count");
        macroN.completeWork;
        macroNStep <= 3;
    endrule

    rule macroNWork2(macroNStep == 3 && macroN.workValid);
        let work = macroN.currentWork;
        dynamicAssert(work.iStart == 0, "macro N transition resets I");
        dynamicAssert(work.jStart == 18, "macro N second tile J");
        dynamicAssert(work.jCount == 16, "macro N second tile J count");
        macroN.completeWork;
        macroNStep <= 4;
    endrule

    rule macroNWork3(macroNStep == 4 && macroN.workValid);
        let work = macroN.currentWork;
        dynamicAssert(work.jStart == 34, "macro N second tile edge J");
        dynamicAssert(work.jCount == 2, "macro N second tile edge count");
        macroN.completeWork;
        macroNStep <= 5;
    endrule

    rule macroNWork4(macroNStep == 5 && macroN.workValid);
        let work = macroN.currentWork;
        dynamicAssert(work.iStart == 0, "final macro N I");
        dynamicAssert(work.jStart == 36, "final macro N J");
        dynamicAssert(work.jCount == 4, "final macro N partial count");
        macroN.completeWork;
        macroNStep <= 6;
    endrule

    rule completeMacroN(macroNStep == 6 && macroN.completionValid);
        dynamicAssert(macroN.completion.stripeId == 0, "macro N completion");
        macroN.consumeCompletion;
        macroNDone <= True;
        macroNStep <= 7;
    endrule

    rule startMacroNEdge(
        macroNEdgeStep == 0 && macroNEdge.startReady
    );
        macroNEdge.start(
            descriptorWithMacroN(4, FullMatrix, 20, 36, 32, 20, 18)
        );
        macroNEdgeStep <= 1;
    endrule

    rule macroNEdgeWork00(
        macroNEdgeStep == 1 && macroNEdge.workValid
    );
        let work = macroNEdge.currentWork;
        dynamicAssert(work.iStart == 0, "macro N edge first I");
        dynamicAssert(work.jStart == 0, "macro N edge first J");
        dynamicAssert(work.iCount == 16, "macro N edge full I count");
        dynamicAssert(work.jCount == 16, "macro N edge full J count");
        macroNEdge.completeWork;
        macroNEdgeStep <= 2;
    endrule

    rule macroNEdgeWork01(
        macroNEdgeStep == 2 && macroNEdge.workValid
    );
        let work = macroNEdge.currentWork;
        dynamicAssert(work.iStart == 0, "macro N edge J-before-I");
        dynamicAssert(work.jStart == 16, "macro N edge partial J");
        dynamicAssert(work.jCount == 2, "macro N edge partial J count");
        macroNEdge.completeWork;
        macroNEdgeStep <= 3;
    endrule

    rule macroNEdgeWork10(
        macroNEdgeStep == 3 && macroNEdge.workValid
    );
        let work = macroNEdge.currentWork;
        dynamicAssert(work.iStart == 16, "macro N edge partial I");
        dynamicAssert(work.jStart == 0, "macro N edge J reset");
        dynamicAssert(work.iCount == 4, "macro N edge partial I count");
        dynamicAssert(work.jCount == 16, "macro N edge reset J count");
        macroNEdge.completeWork;
        macroNEdgeStep <= 4;
    endrule

    rule macroNEdgeWork11(
        macroNEdgeStep == 4 && macroNEdge.workValid
    );
        let work = macroNEdge.currentWork;
        dynamicAssert(work.iStart == 16, "macro N edge final first-tile I");
        dynamicAssert(work.jStart == 16, "macro N edge final first-tile J");
        dynamicAssert(work.iCount == 4, "macro N edge final partial I count");
        dynamicAssert(work.jCount == 2, "macro N edge final partial J count");
        macroNEdge.completeWork;
        macroNEdgeStep <= 5;
    endrule

    rule macroNEdgeWork20(
        macroNEdgeStep == 5 && macroNEdge.workValid
    );
        let work = macroNEdge.currentWork;
        dynamicAssert(work.iStart == 0, "macro N transition resets edge I");
        dynamicAssert(work.jStart == 18, "macro N transition advances edge J");
        dynamicAssert(work.iCount == 16, "macro N second-tile full I count");
        dynamicAssert(work.jCount == 16, "macro N second-tile full J count");
        macroNEdge.completeWork;
        macroNEdgeStep <= 6;
    endrule

    rule macroNEdgeWork21(
        macroNEdgeStep == 6 && macroNEdge.workValid
    );
        let work = macroNEdge.currentWork;
        dynamicAssert(work.iStart == 0, "macro N second tile J-before-I");
        dynamicAssert(work.jStart == 34, "macro N second tile partial J");
        dynamicAssert(work.jCount == 2, "macro N second tile partial J count");
        macroNEdge.completeWork;
        macroNEdgeStep <= 7;
    endrule

    rule macroNEdgeWork30(
        macroNEdgeStep == 7 && macroNEdge.workValid
    );
        let work = macroNEdge.currentWork;
        dynamicAssert(work.iStart == 16, "macro N second tile partial I");
        dynamicAssert(work.jStart == 18, "macro N second tile J reset");
        dynamicAssert(work.iCount == 4, "macro N second tile partial I count");
        dynamicAssert(work.jCount == 16, "macro N second tile reset J count");
        macroNEdge.completeWork;
        macroNEdgeStep <= 8;
    endrule

    rule macroNEdgeWork31(
        macroNEdgeStep == 8 && macroNEdge.workValid
    );
        let work = macroNEdge.currentWork;
        dynamicAssert(work.iStart == 16, "macro N final edge I");
        dynamicAssert(work.jStart == 34, "macro N final edge J");
        dynamicAssert(work.iCount == 4, "macro N final I count");
        dynamicAssert(work.jCount == 2, "macro N final J count");
        macroNEdge.completeWork;
        macroNEdgeStep <= 9;
    endrule

    rule completeMacroNEdge(
        macroNEdgeStep == 9 && macroNEdge.completionValid
    );
        dynamicAssert(
            macroNEdge.completion.stripeId == 0,
            "macro N edge completion"
        );
        macroNEdge.consumeCompletion;
        macroNEdgeDone <= True;
        macroNEdgeStep <= 10;
    endrule

    rule finish(
        fullDone && asyncDone && macroNDone && macroNEdgeDone
    );
        $display("PASS: mkTbMatmulScheduler");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 200) begin
            $display(
                "WATCHDOG fullStep=%0d asyncStep=%0d macroNStep=%0d macroNEdgeStep=%0d",
                fullStep,
                asyncStep,
                macroNStep,
                macroNEdgeStep
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
