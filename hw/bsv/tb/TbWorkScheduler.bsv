package TbWorkScheduler;

import Assert::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import WorkScheduler::*;

function ArrayWork#(dim) makeWork(
    MatrixExtent kStart,
    MatrixExtent kCount
);
    return ArrayWork {
        jobId: 1,
        stripeId: 2,
        stripeRowBegin: 0,
        macroNStart: 0,
        macroNCount: 1,
        iStart: 0,
        jStart: 0,
        iCount: 1,
        jCount: 1,
        kTileStart: kStart,
        kTileCount: kCount
    };
endfunction

(* synthesize *)
module mkTbWorkScheduler(Empty);
    WorkSchedulerIfc#(16) dut16 <- mkWorkScheduler;
    WorkSchedulerIfc#(32) dut32 <- mkWorkScheduler;
    WorkSchedulerIfc#(64) dut64 <- mkWorkScheduler;
    Reg#(UInt#(8)) step <- mkReg(0);

    rule startDim16(step == 0 && dut16.startReady);
        dut16.start(makeWork(0, 32), False);
        step <= 1;
    endrule

    rule checkDim16First(step == 1 && dut16.fragmentValid);
        let fragment = dut16.currentFragment;
        dynamicAssert(fragment.fragmentKStart == 0, "DIM16 first start");
        dynamicAssert(fragment.fragmentKCount == 16, "DIM16 first count");
        dynamicAssert(fragment.fragmentBlockIndex == 0, "DIM16 first block");
        dynamicAssert(!fragment.fragmentEndsBlock, "DIM16 first ends block");
        dynamicAssert(!fragment.accumulate, "DIM16 first accumulate");
        dynamicAssert(dut16.lookaheadValid, "DIM16 lookahead missing");
        dynamicAssert(dut16.lookaheadFragment.fragmentKStart == 16, "DIM16 lookahead start");
        dynamicAssert(dut16.lookaheadFragment.fragmentKCount == 16, "DIM16 lookahead count");
        dynamicAssert(dut16.lookaheadFragment.accumulate, "DIM16 lookahead accumulate");
        dut16.consumeFragment;
        step <= 2;
    endrule

    rule checkDim16Second(step == 2 && dut16.fragmentValid);
        let fragment = dut16.currentFragment;
        dynamicAssert(fragment.fragmentKStart == 16, "DIM16 second start");
        dynamicAssert(fragment.fragmentKCount == 16, "DIM16 second count");
        dynamicAssert(fragment.fragmentEndsBlock, "DIM16 second must end block");
        dynamicAssert(fragment.accumulate, "DIM16 second accumulate");
        dut16.consumeFragment;
        step <= 3;
    endrule

    rule finishDim16(step == 3 && dut16.doneValid);
        dut16.consumeDone;
        step <= 4;
    endrule

    rule startDim32(step == 4 && dut32.startReady);
        dut32.start(makeWork(0, 32), False);
        step <= 5;
    endrule

    rule checkDim32(step == 5 && dut32.fragmentValid);
        let fragment = dut32.currentFragment;
        dynamicAssert(fragment.fragmentKCount == 32, "DIM32 count");
        dynamicAssert(fragment.fragmentEndsBlock, "DIM32 block ending");
        dynamicAssert(!dut32.lookaheadValid, "DIM32 unexpected lookahead");
        dut32.consumeFragment;
        step <= 6;
    endrule

    rule finishDim32(step == 6 && dut32.doneValid);
        dut32.consumeDone;
        step <= 7;
    endrule

    rule startDim64(step == 7 && dut64.startReady);
        dut64.start(makeWork(0, 64), False);
        step <= 8;
    endrule

    rule checkDim64First(step == 8 && dut64.fragmentValid);
        dynamicAssert(dut64.currentFragment.fragmentKCount == 32, "DIM64 first count");
        dynamicAssert(dut64.lookaheadFragment.fragmentKStart == 32, "DIM64 lookahead start");
        dut64.consumeFragment;
        step <= 9;
    endrule

    rule checkDim64Second(step == 9 && dut64.fragmentValid);
        dynamicAssert(dut64.currentFragment.fragmentKStart == 32, "DIM64 second start");
        dynamicAssert(dut64.currentFragment.fragmentKCount == 32, "DIM64 second count");
        dynamicAssert(dut64.currentFragment.fragmentBlockIndex == 1, "DIM64 second block");
        dut64.consumeFragment;
        step <= 10;
    endrule

    rule finishDim64(step == 10 && dut64.doneValid);
        dut64.consumeDone;
        step <= 11;
    endrule

    rule startK48(step == 11 && dut16.startReady);
        dut16.start(makeWork(0, 48), False);
        step <= 12;
    endrule

    rule checkK48First(step == 12 && dut16.fragmentValid);
        dynamicAssert(dut16.currentFragment.fragmentKStart == 0, "K48 first start");
        dynamicAssert(dut16.lookaheadFragment.fragmentKStart == 16, "K48 lookahead start");
        dut16.consumeFragment;
        step <= 13;
    endrule

    rule checkK48Second(step == 13 && dut16.fragmentValid);
        dynamicAssert(dut16.currentFragment.fragmentKStart == 16, "K48 second start");
        dynamicAssert(dut16.lookaheadFragment.fragmentKStart == 32, "K48 third lookahead");
        dut16.consumeFragment;
        step <= 14;
    endrule

    rule checkK48Third(step == 14 && dut16.fragmentValid);
        dynamicAssert(dut16.currentFragment.fragmentKStart == 32, "K48 third start");
        dynamicAssert(dut16.currentFragment.fragmentBlockIndex == 1, "K48 third block");
        dut16.consumeFragment;
        step <= 15;
    endrule

    rule finishK48(step == 15 && dut16.doneValid);
        dut16.consumeDone;
        step <= 16;
    endrule

    rule startNonzeroOrigin(step == 16 && dut16.startReady);
        dut16.start(makeWork(16, 32), True);
        step <= 17;
    endrule

    rule checkNonzeroFirst(step == 17 && dut16.fragmentValid);
        dynamicAssert(dut16.currentFragment.fragmentKStart == 16, "origin first start");
        dynamicAssert(dut16.currentFragment.fragmentBlockIndex == 0, "origin first block");
        dynamicAssert(dut16.currentFragment.accumulate, "origin must accumulate");
        dut16.consumeFragment;
        step <= 18;
    endrule

    rule checkNonzeroSecond(step == 18 && dut16.fragmentValid);
        dynamicAssert(dut16.currentFragment.fragmentKStart == 32, "origin second start");
        dynamicAssert(dut16.currentFragment.fragmentBlockIndex == 1, "origin second block");
        dut16.consumeFragment;
        step <= 19;
    endrule

    rule finishNonzero(step == 19 && dut16.doneValid);
        dut16.consumeDone;
        step <= 20;
    endrule

    rule startInsideBlock(step == 20 && dut16.startReady);
        dut16.start(makeWork(8, 10), False);
        step <= 21;
    endrule

    rule checkInsideBlock(step == 21 && dut16.fragmentValid);
        dynamicAssert(dut16.currentFragment.fragmentKStart == 8, "inside start");
        dynamicAssert(dut16.currentFragment.fragmentKCount == 10, "inside count");
        dynamicAssert(!dut16.currentFragment.fragmentEndsBlock, "inside false block ending");
        dut16.consumeFragment;
        step <= 22;
    endrule

    rule finish(step == 22 && dut16.doneValid);
        dut16.consumeDone;
        $display("PASS: mkTbWorkScheduler");
        $finish(0);
    endrule
endmodule

endpackage
