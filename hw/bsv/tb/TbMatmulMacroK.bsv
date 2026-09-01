package TbMatmulMacroK;

import Assert::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import MatmulScheduler::*;

function AquaMatmulDescriptor descriptor(
    MatmulJobId jobId,
    MatrixExtent m,
    MatrixExtent n,
    MatrixExtent k,
    MatrixExtent stripeRows,
    MatrixExtent macroNTileColumns,
    MatrixExtent macroKTileElements
);
    return AquaMatmulDescriptor {
        jobId: jobId,
        mode: FullMatrix,
        m: m,
        n: n,
        k: k,
        stripeRows: stripeRows,
        macroNTileColumns: macroNTileColumns,
        macroKTileElements: macroKTileElements,
        activationTensor: 1,
        weightTensor: 2,
        outputTensor: 3,
        jobContext: 4
    };
endfunction

(* synthesize *)
module mkTbMatmulMacroK(Empty);
    MatmulSchedulerIfc#(16) single <- mkMatmulScheduler;
    MatmulSchedulerIfc#(16) partition <- mkMatmulScheduler;
    MatmulSchedulerIfc#(16) smallTile <- mkMatmulScheduler;
    MatmulSchedulerIfc#(16) ordering <- mkMatmulScheduler;

    Reg#(UInt#(4)) singleStep <- mkReg(0);
    Reg#(UInt#(4)) partitionStep <- mkReg(0);
    Reg#(UInt#(4)) smallStep <- mkReg(0);
    Reg#(UInt#(8)) orderingStep <- mkReg(0);
    Reg#(UInt#(16)) cycles <- mkReg(0);

    Reg#(Bool) singleDone <- mkReg(False);
    Reg#(Bool) partitionDone <- mkReg(False);
    Reg#(Bool) smallDone <- mkReg(False);
    Reg#(Bool) orderingDone <- mkReg(False);

    rule startSingle(singleStep == 0 && single.startReady);
        single.start(descriptor(1, 1, 1, 48, 1, 1, 48));
        singleStep <= 1;
    endrule

    rule checkSingle(singleStep == 1 && single.workValid);
        let work = single.currentWork;
        dynamicAssert(work.kTileStart == 0, "single macro K start");
        dynamicAssert(work.kTileCount == 48, "single macro K count");
        dynamicAssert(work.stripeRowBegin == 0, "single stripe begin");
        dynamicAssert(work.macroNStart == 0, "single macro N start");
        dynamicAssert(work.macroNCount == 1, "single macro N count");
        single.completeWork;
        singleStep <= 2;
    endrule

    rule completeSingle(singleStep == 2 && single.completionValid);
        single.consumeCompletion;
        singleDone <= True;
        singleStep <= 3;
    endrule

    rule startPartition(
        partitionStep == 0 && partition.startReady
    );
        partition.start(descriptor(2, 1, 1, 80, 1, 1, 32));
        partitionStep <= 1;
    endrule

    rule checkPartition(
        partitionStep >= 1
        && partitionStep <= 3
        && partition.workValid
    );
        let work = partition.currentWork;
        MatrixExtent tileIndex = zeroExtend(partitionStep - 1);
        MatrixExtent expectedStart = tileIndex * 32;
        MatrixExtent expectedCount =
            partitionStep == 3 ? 16 : 32;
        dynamicAssert(
            work.kTileStart == expectedStart,
            "partition macro K start"
        );
        dynamicAssert(
            work.kTileCount == expectedCount,
            "partition macro K count"
        );
        partition.completeWork;
        partitionStep <= partitionStep + 1;
    endrule

    rule completePartition(
        partitionStep == 4 && partition.completionValid
    );
        partition.consumeCompletion;
        partitionDone <= True;
        partitionStep <= 5;
    endrule

    rule startSmall(smallStep == 0 && smallTile.startReady);
        smallTile.start(descriptor(3, 1, 1, 48, 1, 1, 16));
        smallStep <= 1;
    endrule

    rule checkSmall(
        smallStep >= 1 && smallStep <= 3 && smallTile.workValid
    );
        let work = smallTile.currentWork;
        MatrixExtent tileIndex = zeroExtend(smallStep - 1);
        dynamicAssert(
            work.kTileStart == tileIndex * 16,
            "small macro K start"
        );
        dynamicAssert(work.kTileCount == 16, "small macro K count");
        smallTile.completeWork;
        smallStep <= smallStep + 1;
    endrule

    rule completeSmall(smallStep == 4 && smallTile.completionValid);
        smallTile.consumeCompletion;
        smallDone <= True;
        smallStep <= 5;
    endrule

    rule startOrdering(
        orderingStep == 0 && ordering.startReady
    );
        ordering.start(descriptor(4, 17, 40, 80, 17, 24, 32));
        orderingStep <= 1;
    endrule

    rule checkOrdering(
        orderingStep >= 1
        && orderingStep <= 18
        && ordering.workValid
    );
        let work = ordering.currentWork;
        UInt#(8) workIndex = orderingStep - 1;
        Bool firstMacroN = workIndex < 12;
        UInt#(8) localIndex =
            firstMacroN ? workIndex : workIndex - 12;
        UInt#(8) macroKIndex =
            firstMacroN ? localIndex / 4 : localIndex / 2;
        UInt#(8) spatialIndex =
            firstMacroN ? localIndex % 4 : localIndex % 2;
        UInt#(8) iGroup =
            firstMacroN ? spatialIndex / 2 : spatialIndex;
        UInt#(8) jGroup =
            firstMacroN ? spatialIndex % 2 : 0;

        MatrixExtent expectedMacroNStart =
            firstMacroN ? 0 : 24;
        MatrixExtent expectedMacroNCount =
            firstMacroN ? 24 : 16;
        MatrixExtent expectedIStart = zeroExtend(iGroup) * 16;
        MatrixExtent expectedJStart =
            expectedMacroNStart + zeroExtend(jGroup) * 16;
        MatrixExtent expectedKStart =
            zeroExtend(macroKIndex) * 32;
        MatrixExtent expectedKCount =
            macroKIndex == 2 ? 16 : 32;

        dynamicAssert(work.stripeRowBegin == 0, "ordering stripe begin");
        dynamicAssert(
            work.macroNStart == expectedMacroNStart,
            "ordering macro N start"
        );
        dynamicAssert(
            work.macroNCount == expectedMacroNCount,
            "ordering macro N count"
        );
        dynamicAssert(work.iStart == expectedIStart, "ordering I start");
        dynamicAssert(work.jStart == expectedJStart, "ordering J start");
        dynamicAssert(
            work.iCount == (iGroup == 0 ? 16 : 1),
            "ordering I count"
        );
        dynamicAssert(
            work.jCount == (
                firstMacroN && jGroup == 1 ? 8 : 16
            ),
            "ordering J count"
        );
        dynamicAssert(
            work.kTileStart == expectedKStart,
            "ordering macro K start"
        );
        dynamicAssert(
            work.kTileCount == expectedKCount,
            "ordering macro K count"
        );

        ordering.completeWork;
        orderingStep <= orderingStep + 1;
    endrule

    rule completeOrdering(
        orderingStep == 19 && ordering.completionValid
    );
        ordering.consumeCompletion;
        orderingDone <= True;
        orderingStep <= 20;
    endrule

    rule finish(
        singleDone && partitionDone && smallDone && orderingDone
    );
        $display("PASS mkTbMatmulMacroK");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 300) begin
            $display(
                "WATCHDOG single=%0d partition=%0d small=%0d ordering=%0d",
                singleStep,
                partitionStep,
                smallStep,
                orderingStep
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
