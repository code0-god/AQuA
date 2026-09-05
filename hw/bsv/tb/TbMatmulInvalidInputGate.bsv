package TbMatmulInvalidInputGate;

import AquaTypes::*;
import AquaWorkTypes::*;
import MatmulScheduler::*;

function AquaMatmulDescriptor validDescriptor;
    return AquaMatmulDescriptor {
        jobId: 1,
        mode: AsyncStripes,
        m: 24,
        n: 16,
        k: 32,
        stripeRows: 16,
        macroNTileColumns: 16,
        macroKTileElements: 32,
        activationTensor: 1,
        weightTensor: 2,
        outputTensor: 3,
        jobContext: 4
    };
endfunction

function AquaMatmulDescriptor invalidDescriptor;
    return AquaMatmulDescriptor {
        jobId: 1,
        mode: AsyncStripes,
        m: 0,
        n: 16,
        k: 32,
        stripeRows: 16,
        macroNTileColumns: 16,
        macroKTileElements: 32,
        activationTensor: 1,
        weightTensor: 2,
        outputTensor: 3,
        jobContext: 4
    };
endfunction

function AquaMatmulDescriptor invalidMacroKZeroDescriptor;
    return AquaMatmulDescriptor {
        jobId: 1,
        mode: AsyncStripes,
        m: 24,
        n: 16,
        k: 32,
        stripeRows: 16,
        macroNTileColumns: 16,
        macroKTileElements: 0,
        activationTensor: 1,
        weightTensor: 2,
        outputTensor: 3,
        jobContext: 4
    };
endfunction

function AquaMatmulDescriptor invalidMacroKLargeDescriptor;
    return AquaMatmulDescriptor {
        jobId: 1,
        mode: AsyncStripes,
        m: 24,
        n: 16,
        k: 32,
        stripeRows: 16,
        macroNTileColumns: 16,
        macroKTileElements: 33,
        activationTensor: 1,
        weightTensor: 2,
        outputTensor: 3,
        jobContext: 4
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
        activationBase: unpack(0),
        stripeContext: zeroExtend(stripeId)
    };
endfunction

(* synthesize *)
module mkTbMatmulInvalidInputGate(Empty);
    MatmulSchedulerIfc#(16) descriptorDut <- mkMatmulScheduler;
    MatmulSchedulerIfc#(16) gapDut <- mkMatmulScheduler;
    MatmulSchedulerIfc#(16) overlapDut <- mkMatmulScheduler;
    MatmulSchedulerIfc#(16) boundsDut <- mkMatmulScheduler;
    MatmulSchedulerIfc#(16) idDut <- mkMatmulScheduler;

    Reg#(UInt#(4)) descriptorStep <- mkReg(0);
    Reg#(UInt#(4)) gapStep <- mkReg(0);
    Reg#(UInt#(4)) overlapStep <- mkReg(0);
    Reg#(UInt#(4)) boundsStep <- mkReg(0);
    Reg#(UInt#(4)) idStep <- mkReg(0);
    Reg#(Bool) descriptorDone <- mkReg(False);
    Reg#(Bool) gapDone <- mkReg(False);
    Reg#(Bool) overlapDone <- mkReg(False);
    Reg#(Bool) boundsDone <- mkReg(False);
    Reg#(Bool) idDone <- mkReg(False);
    Reg#(UInt#(8)) cycles <- mkReg(0);

    rule sendInvalidDescriptor(
        descriptorStep == 0 && descriptorDut.startReady
    );
        descriptorDut.start(invalidDescriptor);
        descriptorStep <= 1;
    endrule

    rule verifyInvalidDescriptor(descriptorStep == 1);
        if (
            descriptorDut.startReady
            && !descriptorDut.workValid
            && !descriptorDut.publishReady
            && !descriptorDut.lookaheadValid
            && !descriptorDut.completionValid
        ) begin
            descriptorStep <= 2;
        end
        else begin
            $display("FAIL invalid descriptor changed scheduler state");
            $finish(1);
        end
    endrule

    rule sendInvalidMacroKZero(
        descriptorStep == 2 && descriptorDut.startReady
    );
        descriptorDut.start(invalidMacroKZeroDescriptor);
        descriptorStep <= 3;
    endrule

    rule verifyInvalidMacroKZero(descriptorStep == 3);
        if (
            descriptorDut.startReady
            && !descriptorDut.workValid
            && !descriptorDut.publishReady
            && !descriptorDut.lookaheadValid
            && !descriptorDut.completionValid
        ) begin
            descriptorStep <= 4;
        end
        else begin
            $display("FAIL zero macro K changed scheduler state");
            $finish(1);
        end
    endrule

    rule sendInvalidMacroKLarge(
        descriptorStep == 4 && descriptorDut.startReady
    );
        descriptorDut.start(invalidMacroKLargeDescriptor);
        descriptorStep <= 5;
    endrule

    rule verifyInvalidMacroKLarge(descriptorStep == 5);
        if (
            descriptorDut.startReady
            && !descriptorDut.workValid
            && !descriptorDut.publishReady
            && !descriptorDut.lookaheadValid
            && !descriptorDut.completionValid
        ) begin
            descriptorDone <= True;
            descriptorStep <= 6;
        end
        else begin
            $display("FAIL oversized macro K changed scheduler state");
            $finish(1);
        end
    endrule

    rule startGap(gapStep == 0 && gapDut.startReady);
        gapDut.start(validDescriptor);
        gapStep <= 1;
    endrule

    rule publishGap(gapStep == 1 && gapDut.publishReady);
        gapDut.publishStripe(stripe(0, 1, 16));
        gapStep <= 2;
    endrule

    rule verifyGapRejected(gapStep == 2);
        if (
            gapDut.publishReady
            && !gapDut.workValid
            && !gapDut.lookaheadValid
        ) begin
            gapStep <= 3;
        end
        else begin
            $display("FAIL stripe gap changed publication state");
            $finish(1);
        end
    endrule

    rule publishGapRecovery(gapStep == 3 && gapDut.publishReady);
        gapDut.publishStripe(stripe(0, 0, 16));
        gapStep <= 4;
    endrule

    rule verifyGapRecovery(gapStep == 4);
        if (
            gapDut.workValid
            && gapDut.currentWork.stripeId == 0
            && gapDut.currentWork.iStart == 0
        ) begin
            gapDone <= True;
            gapStep <= 5;
        end
        else begin
            $display("FAIL valid stripe did not recover after gap");
            $finish(1);
        end
    endrule

    rule startOverlap(overlapStep == 0 && overlapDut.startReady);
        overlapDut.start(validDescriptor);
        overlapStep <= 1;
    endrule

    rule publishOverlapBase(
        overlapStep == 1 && overlapDut.publishReady
    );
        overlapDut.publishStripe(stripe(0, 0, 16));
        overlapStep <= 2;
    endrule

    rule publishOverlap(overlapStep == 2 && overlapDut.publishReady);
        overlapDut.publishStripe(stripe(1, 8, 8));
        overlapStep <= 3;
    endrule

    rule verifyOverlapRejected(overlapStep == 3);
        if (
            overlapDut.workValid
            && overlapDut.currentWork.stripeId == 0
            && overlapDut.currentWork.iStart == 0
            && !overlapDut.lookaheadValid
            && overlapDut.publishReady
        ) begin
            overlapStep <= 4;
        end
        else begin
            $display("FAIL stripe overlap changed publication state");
            $finish(1);
        end
    endrule

    rule publishOverlapRecovery(
        overlapStep == 4 && overlapDut.publishReady
    );
        overlapDut.publishStripe(stripe(1, 16, 8));
        overlapStep <= 5;
    endrule

    rule verifyOverlapRecovery(overlapStep == 5);
        if (
            overlapDut.lookaheadValid
            && overlapDut.lookaheadStripe.stripeId == 1
        ) begin
            overlapDone <= True;
            overlapStep <= 6;
        end
        else begin
            $display("FAIL valid stripe did not recover after overlap");
            $finish(1);
        end
    endrule

    rule startBounds(boundsStep == 0 && boundsDut.startReady);
        boundsDut.start(validDescriptor);
        boundsStep <= 1;
    endrule

    rule publishBoundsBase(boundsStep == 1 && boundsDut.publishReady);
        boundsDut.publishStripe(stripe(0, 0, 16));
        boundsStep <= 2;
    endrule

    rule publishOutOfBounds(
        boundsStep == 2 && boundsDut.publishReady
    );
        boundsDut.publishStripe(stripe(1, 16, 16));
        boundsStep <= 3;
    endrule

    rule verifyBoundsRejected(boundsStep == 3);
        if (
            boundsDut.workValid
            && boundsDut.currentWork.stripeId == 0
            && boundsDut.currentWork.iStart == 0
            && !boundsDut.lookaheadValid
            && boundsDut.publishReady
        ) begin
            boundsStep <= 4;
        end
        else begin
            $display("FAIL out-of-bounds stripe changed publication state");
            $finish(1);
        end
    endrule

    rule publishBoundsRecovery(
        boundsStep == 4 && boundsDut.publishReady
    );
        boundsDut.publishStripe(stripe(1, 16, 8));
        boundsStep <= 5;
    endrule

    rule verifyBoundsRecovery(boundsStep == 5);
        if (
            boundsDut.lookaheadValid
            && boundsDut.lookaheadStripe.stripeId == 1
        ) begin
            boundsDone <= True;
            boundsStep <= 6;
        end
        else begin
            $display("FAIL valid stripe did not recover after bounds");
            $finish(1);
        end
    endrule

    rule startWrongId(idStep == 0 && idDut.startReady);
        idDut.start(validDescriptor);
        idStep <= 1;
    endrule

    rule publishIdBase(idStep == 1 && idDut.publishReady);
        idDut.publishStripe(stripe(0, 0, 16));
        idStep <= 2;
    endrule

    rule publishWrongId(idStep == 2 && idDut.publishReady);
        idDut.publishStripe(stripe(2, 16, 8));
        idStep <= 3;
    endrule

    rule verifyWrongIdRejected(idStep == 3);
        if (
            idDut.workValid
            && idDut.currentWork.stripeId == 0
            && idDut.currentWork.iStart == 0
            && !idDut.lookaheadValid
            && idDut.publishReady
        ) begin
            idStep <= 4;
        end
        else begin
            $display("FAIL wrong stripe ID changed publication state");
            $finish(1);
        end
    endrule

    rule publishIdRecovery(idStep == 4 && idDut.publishReady);
        idDut.publishStripe(stripe(1, 16, 8));
        idStep <= 5;
    endrule

    rule verifyIdRecovery(idStep == 5);
        if (
            idDut.lookaheadValid
            && idDut.lookaheadStripe.stripeId == 1
        ) begin
            idDone <= True;
            idStep <= 6;
        end
        else begin
            $display("FAIL valid stripe did not recover after wrong ID");
            $finish(1);
        end
    endrule

    rule finish(
        descriptorDone
        && gapDone
        && overlapDone
        && boundsDone
        && idDone
    );
        $display("PASS: mkTbMatmulInvalidInputGate");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 50) begin
            $display(
                "FAIL watchdog descriptor=%0d gap=%0d overlap=%0d bounds=%0d id=%0d",
                descriptorStep,
                gapStep,
                overlapStep,
                boundsStep,
                idStep
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
