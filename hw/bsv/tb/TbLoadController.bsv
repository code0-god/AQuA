package TbLoadController;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryTypes::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import LoadChannel::*;
import LoadController::*;

function DefaultAquaLocalAddr localAddress(
    AquaLocalRegion region,
    Bit#(16) row
);
    return DefaultAquaLocalAddr {
        region: region,
        slot: 1,
        bank: 0,
        row: row
    };
endfunction

function ProviderLoadWork#(16) loadWork(UInt#(3) phase);
    Bool newJ = phase >= 3;
    MatrixExtent blockIndex = phase < 2 ? 0 : 1;
    Bool movedMetadata = phase == 4;
    return ProviderLoadWork {
        jobId: 7,
        stripeId: 3,
        macroTileId: 5,
        arrayWorkId: newJ ? 11 : 10,
        fragmentId: 20 + zeroExtend(phase),
        activationTensor: 101,
        weightTensor: 202,
        iStart: 4,
        iCount: 2,
        jStart: newJ ? 12 : 8,
        jCount: 3,
        fragmentKStart: zeroExtend(phase) * 8,
        fragmentKCount: 8,
        fragmentBlockIndex: blockIndex,
        activationBase: localAddress(LocalActivation, 1),
        weightBase: localAddress(LocalWeight, 4),
        blockShiftDestination: localAddress(
            LocalHp1Meta,
            movedMetadata ? 10 : 7
        ),
        rowScaleDestination: localAddress(
            LocalHp1Meta,
            movedMetadata ? 11 : 8
        )
    };
endfunction

(* descending_urgency = "consumeActivation, dut_issueActivation, consumeWeight, dut_issueWeight, consumeBlockShift, dut_issueBlockShift, consumeRowScale, dut_issueRowScale" *)
module mkTbLoadController(Empty);
    LoadControllerIfc#(16, 2, 16) dut <- mkLoadController;

    Reg#(UInt#(3)) phase <- mkReg(0);
    Reg#(Bool) running <- mkReg(False);
    Reg#(UInt#(8)) activationRequests <- mkReg(0);
    Reg#(UInt#(8)) weightRequests <- mkReg(0);
    Reg#(UInt#(8)) blockRequests <- mkReg(0);
    Reg#(UInt#(8)) rowRequests <- mkReg(0);
    Reg#(UInt#(4)) activationStall <- mkReg(0);
    Reg#(UInt#(16)) cycles <- mkReg(0);

    rule startPhase(!running && phase < 5 && dut.scheduleReady);
        dut.schedule(loadWork(phase));
        running <= True;
    endrule

    rule stallFirstActivation(
        running
        && phase == 0
        && dut.activationRequests.requestValid
        && activationStall < 3
    );
        if (activationStall == 2) begin
            dynamicAssert(weightRequests > 0,
                          "weight channel stalled behind activation");
            dynamicAssert(blockRequests > 0 && rowRequests > 0,
                          "metadata channels stalled behind activation");
        end
        activationStall <= activationStall + 1;
    endrule

    rule consumeActivation(
        running
        && dut.activationRequests.requestValid
        && !dut.completionValid
        && !(phase == 0 && activationStall < 3)
    );
        let request = dut.activationRequests.request;
        let expected = loadWork(phase);
        dynamicAssert(request.tag.kind == MemoryActivation,
                      "activation request kind mismatch");
        dynamicAssert(request.tag.jobId == expected.jobId,
                      "activation job tag mismatch");
        dynamicAssert(request.tag.stripeId == expected.stripeId,
                      "activation stripe tag mismatch");
        dynamicAssert(request.tag.macroTileId == expected.macroTileId,
                      "activation macro tile tag mismatch");
        dynamicAssert(request.tag.arrayWorkId == expected.arrayWorkId,
                      "activation array work tag mismatch");
        dynamicAssert(request.tag.fragmentId == expected.fragmentId,
                      "activation fragment tag mismatch");
        dynamicAssert(request.tensorId == expected.activationTensor,
                      "activation tensor mismatch");
        dynamicAssert(request.outer.start >= expected.iStart,
                      "activation row range starts early");
        dynamicAssert(request.outer.start < expected.iStart + 2,
                      "activation row range starts late");
        dynamicAssert(request.outer.count == 1,
                      "activation request must cover one row");
        dynamicAssert(request.inner.start == expected.fragmentKStart,
                      "activation K start mismatch");
        dynamicAssert(request.inner.count == expected.fragmentKCount,
                      "activation K count mismatch");
        dynamicAssert(request.tag.localDestination.region == LocalActivation,
                      "activation destination region mismatch");
        AquaMemoryTag wrongTag = request.tag;
        wrongTag.jobId = request.tag.jobId + 1;
        dynamicAssert(!dut.queuedActivationResponseReady(wrongTag),
                      "wrong-work activation response was accepted");
        dynamicAssert(dut.queuedActivationResponseReady(request.tag),
                      "activation response unexpectedly backpressured");
        dut.completeQueuedActivation(request.tag);
        activationRequests <= activationRequests + 1;
    endrule

    rule consumeWeight(
        running
        && dut.weightRequests.requestValid
        && !dut.completionValid
    );
        let request = dut.weightRequests.request;
        let expected = loadWork(phase);
        dynamicAssert(request.tag.kind == MemoryWeightCode,
                      "weight request kind mismatch");
        dynamicAssert(request.tensorId == expected.weightTensor,
                      "weight tensor mismatch");
        // Canonical provider orientation is one J row over one K fragment.
        dynamicAssert(request.outer.start >= expected.jStart,
                      "weight J range starts early");
        dynamicAssert(request.outer.start < expected.jStart + 3,
                      "weight J range starts late");
        dynamicAssert(request.outer.count == 1,
                      "weight request must cover one J row");
        dynamicAssert(request.inner.start == expected.fragmentKStart,
                      "weight K start mismatch");
        dynamicAssert(request.inner.count == expected.fragmentKCount,
                      "weight K count mismatch");
        dynamicAssert(request.tag.localDestination.region == LocalWeight,
                      "weight destination region mismatch");
        dynamicAssert(dut.queuedWeightResponseReady(request.tag),
                      "weight response unexpectedly backpressured");
        dut.completeQueuedWeight(request.tag);
        weightRequests <= weightRequests + 1;
    endrule

    rule consumeBlockShift(
        running
        && dut.blockShiftRequests.requestValid
        && !dut.completionValid
    );
        let request = dut.blockShiftRequests.request;
        let expected = loadWork(phase);
        dynamicAssert(request.tag.kind == MemoryHp1BlockShift,
                      "block shift request kind mismatch");
        dynamicAssert(request.outer.start == expected.jStart,
                      "block shift J start mismatch");
        dynamicAssert(request.outer.count == zeroExtend(expected.jCount),
                      "block shift J count mismatch");
        dynamicAssert(
            request.inner.start == expected.fragmentBlockIndex,
            "block shift block mismatch"
        );
        dynamicAssert(request.tag.localDestination.region == LocalHp1Meta,
                      "block shift destination mismatch");
        dynamicAssert(dut.queuedBlockShiftResponseReady(request.tag),
                      "block shift response unexpectedly backpressured");
        dut.completeQueuedBlockShift(request.tag);
        blockRequests <= blockRequests + 1;
    endrule

    rule consumeRowScale(
        running
        && dut.rowScaleRequests.requestValid
        && !dut.completionValid
    );
        let request = dut.rowScaleRequests.request;
        let expected = loadWork(phase);
        dynamicAssert(request.tag.kind == MemoryHp1RowScale,
                      "row scale request kind mismatch");
        dynamicAssert(request.outer.start == expected.jStart,
                      "row scale J start mismatch");
        dynamicAssert(request.outer.count == zeroExtend(expected.jCount),
                      "row scale J count mismatch");
        dynamicAssert(request.tag.localDestination.region == LocalHp1Meta,
                      "row scale destination mismatch");
        dynamicAssert(dut.queuedRowScaleResponseReady(request.tag),
                      "row scale response unexpectedly backpressured");
        dut.completeQueuedRowScale(request.tag);
        rowRequests <= rowRequests + 1;
    endrule

    rule finishPhase(running && dut.completionValid);
        let completion = dut.completion;
        let expected = loadWork(phase);
        dynamicAssert(completion.jobId == expected.jobId,
                      "load completion job mismatch");
        dynamicAssert(completion.fragmentId == expected.fragmentId,
                      "load completion fragment mismatch");
        case (phase)
            0: begin
                dynamicAssert(activationRequests == 2,
                              "phase zero activation count mismatch");
                dynamicAssert(weightRequests == 3,
                              "phase zero weight count mismatch");
                dynamicAssert(blockRequests == 1,
                              "phase zero block request count mismatch");
                dynamicAssert(rowRequests == 1,
                              "phase zero row request count mismatch");
            end
            1: begin
                dynamicAssert(activationRequests == 4,
                              "same-block activation count mismatch");
                dynamicAssert(weightRequests == 6,
                              "same-block weight count mismatch");
                dynamicAssert(blockRequests == 1,
                              "same-block shift was requested twice");
                dynamicAssert(rowRequests == 1,
                              "same-J row scale was requested twice");
            end
            2: begin
                dynamicAssert(blockRequests == 2,
                              "new block did not request block shift");
                dynamicAssert(rowRequests == 1,
                              "new block reloaded row scale");
            end
            3: begin
                dynamicAssert(activationRequests == 8,
                              "final activation count mismatch");
                dynamicAssert(weightRequests == 12,
                              "final weight count mismatch");
                dynamicAssert(blockRequests == 3,
                              "new J did not request block shift");
                dynamicAssert(rowRequests == 2,
                              "new J did not request row scale");
            end
            4: begin
                dynamicAssert(activationRequests == 10,
                              "relocated activation count mismatch");
                dynamicAssert(weightRequests == 15,
                              "relocated weight count mismatch");
                dynamicAssert(blockRequests == 4,
                              "relocated block metadata was reused");
                dynamicAssert(rowRequests == 3,
                              "relocated row metadata was reused");
            end
        endcase
        dut.consumeCompletion;
        running <= False;
        phase <= phase + 1;
    endrule

    rule finish(phase == 5 && !running);
        dynamicAssert(dut.outstandingCycles > 0,
                      "provider staging cycles were not counted");
        $display("PASS mkTbLoadController");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 400) begin
            $display("WATCHDOG phase=%0d", phase);
            $finish(1);
        end
    endrule
endmodule

endpackage
