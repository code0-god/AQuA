package TbLoadController;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import LoadController::*;

function AquaLocalAddr localAddress(
    AquaLocalRegion region,
    Bit#(16) row
);
    return AquaLocalAddr { region: region, bank: 0, row: row };
endfunction

function ProviderLoadWork#(16) loadWork(UInt#(3) phase);
    Bool newJ = phase >= 3;
    MatrixExtent blockIndex = phase < 2 ? 0 : 1;
    Bool movedMetadata = phase == 4;
    return ProviderLoadWork {
        jobId: 7,
        stripeId: 3,
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

// G0010 is testbench-only: consume/respond rules drain before guarded phase transitions, so no urgency attribute is needed.
module mkTbLoadController(Empty);
    LoadControllerIfc#(16, 2, 16, 3, 17, 16, 16) dut
        <- mkLoadController;

    Reg#(UInt#(3)) phase <- mkReg(0);
    Reg#(Bool) running <- mkReg(False);
    Reg#(UInt#(8)) activationRequests <- mkReg(0);
    Reg#(UInt#(8)) weightRequests <- mkReg(0);
    Reg#(UInt#(8)) blockRequests <- mkReg(0);
    Reg#(UInt#(8)) rowRequests <- mkReg(0);
    Reg#(UInt#(4)) activationStall <- mkReg(0);
    Reg#(Maybe#(AquaMemoryTag)) pendingActivation <- mkReg(tagged Invalid);
    Reg#(Maybe#(AquaMemoryTag)) pendingWeight <- mkReg(tagged Invalid);
    Reg#(Maybe#(AquaMemoryTag)) pendingBlock <- mkReg(tagged Invalid);
    Reg#(Maybe#(AquaMemoryTag)) pendingRow <- mkReg(tagged Invalid);
    Reg#(UInt#(16)) cycles <- mkReg(0);

    rule startPhase(!running && phase < 5 && dut.scheduleReady);
        dut.schedule(loadWork(phase));
        running <= True;
    endrule

    rule stallFirstActivation(
        running
        && phase == 0
        && dut.activationPort.requests.valid
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
        && dut.activationPort.requests.valid
        && !isValid(pendingActivation)
        && !(phase == 0 && activationStall < 3)
    );
        let request = dut.activationPort.requests.first;
        let expected = loadWork(phase);
        dynamicAssert(request.tag.jobId == expected.jobId,
                      "activation job tag mismatch");
        dynamicAssert(request.tag.stripeId == expected.stripeId,
                      "activation stripe tag mismatch");
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
        dynamicAssert(request.inner.start == expected.fragmentKStart,
                      "activation K start mismatch");
        dynamicAssert(request.inner.count == zeroExtend(expected.fragmentKCount),
                      "activation K count mismatch");
        dynamicAssert(request.tag.localAddress.region == LocalActivation,
                      "activation destination region mismatch");
        dynamicAssert(!dut.activationPort.responses.ready(request.tag),
                      "activation response accepted before request consume");
        dut.activationPort.requests.consume;
        pendingActivation <= tagged Valid request.tag;
        activationRequests <= activationRequests + 1;
    endrule

    rule respondActivation(isValid(pendingActivation));
        AquaMemoryTag exact = fromMaybe(?, pendingActivation);
        AquaMemoryTag wrong = exact;
        wrong.jobId = exact.jobId + 1;
        dynamicAssert(!dut.activationPort.responses.ready(wrong),
                      "wrong activation job ID accepted");
        wrong = exact;
        wrong.stripeId = exact.stripeId + 1;
        dynamicAssert(!dut.activationPort.responses.ready(wrong),
                      "wrong activation stripe ID accepted");
        wrong = exact;
        wrong.arrayWorkId = exact.arrayWorkId + 1;
        dynamicAssert(!dut.activationPort.responses.ready(wrong),
                      "wrong activation array work ID accepted");
        wrong = exact;
        wrong.fragmentId = exact.fragmentId + 1;
        dynamicAssert(!dut.activationPort.responses.ready(wrong),
                      "wrong activation fragment ID accepted");
        wrong = exact;
        wrong.transactionId = exact.transactionId + 1;
        dynamicAssert(!dut.activationPort.responses.ready(wrong),
                      "wrong activation transaction ID accepted");
        wrong = exact;
        wrong.localAddress.row = exact.localAddress.row + 1;
        dynamicAssert(!dut.activationPort.responses.ready(wrong),
                      "wrong activation local address accepted");
        dynamicAssert(dut.activationPort.responses.ready(exact),
                      "exact activation response rejected after consume");
        dut.activationPort.responses.put(exact);
        pendingActivation <= tagged Invalid;
    endrule

    rule consumeWeight(
        running
        && dut.weightPort.requests.valid
        && !isValid(pendingWeight)
    );
        let request = dut.weightPort.requests.first;
        let expected = loadWork(phase);
        dynamicAssert(request.tensorId == expected.weightTensor,
                      "weight tensor mismatch");
        dynamicAssert(request.outer.start >= expected.jStart,
                      "weight J range starts early");
        dynamicAssert(request.outer.start < expected.jStart + 3,
                      "weight J range starts late");
        dynamicAssert(request.inner.start == expected.fragmentKStart,
                      "weight K start mismatch");
        dynamicAssert(!dut.weightPort.responses.ready(request.tag),
                      "weight response accepted before request consume");
        dut.weightPort.requests.consume;
        pendingWeight <= tagged Valid request.tag;
        weightRequests <= weightRequests + 1;
    endrule

    rule respondWeight(isValid(pendingWeight));
        let tag = fromMaybe(?, pendingWeight);
        dynamicAssert(dut.weightPort.responses.ready(tag),
                      "exact weight response rejected after consume");
        dut.weightPort.responses.put(tag);
        pendingWeight <= tagged Invalid;
    endrule

    rule consumeBlockShift(
        running
        && dut.blockShiftPort.requests.valid
        && !isValid(pendingBlock)
    );
        let request = dut.blockShiftPort.requests.first;
        let expected = loadWork(phase);
        dynamicAssert(request.outer.start == expected.jStart,
                      "block shift J start mismatch");
        dynamicAssert(request.outer.count == zeroExtend(expected.jCount),
                      "block shift J count mismatch");
        dynamicAssert(request.inner.start == expected.fragmentBlockIndex,
                      "block shift block mismatch");
        dynamicAssert(!dut.blockShiftPort.responses.ready(request.tag),
                      "block response accepted before request consume");
        dut.blockShiftPort.requests.consume;
        pendingBlock <= tagged Valid request.tag;
        blockRequests <= blockRequests + 1;
    endrule

    rule respondBlockShift(isValid(pendingBlock));
        let tag = fromMaybe(?, pendingBlock);
        dynamicAssert(dut.blockShiftPort.responses.ready(tag),
                      "exact block response rejected after consume");
        dut.blockShiftPort.responses.put(tag);
        pendingBlock <= tagged Invalid;
    endrule

    rule consumeRowShift(
        running
        && dut.rowShiftPort.requests.valid
        && !isValid(pendingRow)
    );
        let request = dut.rowShiftPort.requests.first;
        let expected = loadWork(phase);
        dynamicAssert(request.outer.start == expected.jStart,
                      "row shift J start mismatch");
        dynamicAssert(request.outer.count == zeroExtend(expected.jCount),
                      "row shift J count mismatch");
        dynamicAssert(!dut.rowShiftPort.responses.ready(request.tag),
                      "row response accepted before request consume");
        dut.rowShiftPort.requests.consume;
        pendingRow <= tagged Valid request.tag;
        rowRequests <= rowRequests + 1;
    endrule

    rule respondRowShift(isValid(pendingRow));
        let tag = fromMaybe(?, pendingRow);
        dynamicAssert(dut.rowShiftPort.responses.ready(tag),
                      "exact row response rejected after consume");
        dut.rowShiftPort.responses.put(tag);
        pendingRow <= tagged Invalid;
    endrule

    rule assertSingleOutstandingActivation(isValid(pendingActivation));
        dynamicAssert(!dut.activationPort.requests.valid,
                      "activation channel issued more than one outstanding request");
    endrule
    rule assertSingleOutstandingWeight(isValid(pendingWeight));
        dynamicAssert(!dut.weightPort.requests.valid,
                      "weight channel issued more than one outstanding request");
    endrule
    rule assertSingleOutstandingBlock(isValid(pendingBlock));
        dynamicAssert(!dut.blockShiftPort.requests.valid,
                      "block channel issued more than one outstanding request");
    endrule
    rule assertSingleOutstandingRow(isValid(pendingRow));
        dynamicAssert(!dut.rowShiftPort.requests.valid,
                      "row channel issued more than one outstanding request");
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
                              "same-J row shift was requested twice");
            end
            2: begin
                dynamicAssert(blockRequests == 2,
                              "new block did not request block shift");
                dynamicAssert(rowRequests == 1,
                              "new block reloaded row shift");
            end
            3: begin
                dynamicAssert(activationRequests == 8,
                              "final activation count mismatch");
                dynamicAssert(weightRequests == 12,
                              "final weight count mismatch");
                dynamicAssert(blockRequests == 3,
                              "new J did not request block shift");
                dynamicAssert(rowRequests == 2,
                              "new J did not request row shift");
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
        if (cycles == 500) begin
            $display("WATCHDOG phase=%0d", phase);
            $finish(1);
        end
    endrule
endmodule

endpackage
