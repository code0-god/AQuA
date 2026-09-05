package TbMemoryDepth;

import AccumulatorMem::*;
import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import Hp1MetaMem::*;
import LoadStager::*;
import Scratchpad::*;
import StoreController::*;
import Vector::*;

function Vector#(1, Int#(8)) intRow(Int#(8) value);
    return replicate(value);
endfunction

function Vector#(1, Hp1BlockScale#(4)) blockRow(UInt#(4) shift);
    return replicate(Hp1BlockScale { zeroBlock: False, leftShift: shift });
endfunction

function Vector#(1, UInt#(4)) shiftRow(UInt#(4) shift);
    return replicate(shift);
endfunction

function AquaMemoryTag localTag(AquaLocalRegion region, Bit#(16) row);
    return AquaMemoryTag {
        jobId: 0,
        stripeId: 0,
        arrayWorkId: 0,
        fragmentId: 0,
        transactionId: 0,
        localAddress: AquaLocalAddr { region: region, bank: 0, row: row }
    };
endfunction

function StoreWork#(16) storeWorkAt(Bit#(16) row);
    return StoreWork {
        jobId: 0,
        stripeId: 0,
        arrayWorkId: 0,
        outputTensor: 0,
        iStart: 0,
        iCount: 1,
        jStart: 0,
        jCount: 1,
        accumulatorBase: AquaLocalAddr {
            region: LocalAccumulator,
            bank: 0,
            row: row
        }
    };
endfunction

(* synthesize *)
module mkTbMemoryDepth(Empty);
    ScratchpadBankIfc#(1, 1, Int#(8)) scratch1 <- mkScratchpadBank;
    ScratchpadBankIfc#(8, 1, Int#(8)) scratch8 <- mkScratchpadBank;
    ScratchpadBankIfc#(17, 1, Int#(8)) scratch17 <- mkScratchpadBank;
    Hp1MetaMemIfc#(1, 1, 1, 4, 4) hp1 <- mkHp1MetaMem;
    Hp1MetaMemIfc#(8, 8, 1, 4, 4) hp8 <- mkHp1MetaMem;
    Hp1MetaMemIfc#(17, 17, 1, 4, 4) hp17 <- mkHp1MetaMem;
    AccumulatorMemIfc#(1, 1, 8) accumulator1 <- mkAccumulatorMem;
    AccumulatorMemIfc#(1, 8, 8) accumulator8 <- mkAccumulatorMem;
    AccumulatorMemIfc#(1, 17, 8) accumulator17 <- mkAccumulatorMem;
    Reg#(UInt#(5)) step <- mkReg(0);
    Reg#(UInt#(8)) cycles <- mkReg(0);

    rule watchdog(cycles < 100);
        cycles <= cycles + 1;
    endrule

    rule timeout(cycles >= 100);
        $display("FAIL: mkTbMemoryDepth timed out");
        $finish(1);
    endrule

    rule validateWideBoundaries(step == 0);
        for (Integer index = 0; index < 3; index = index + 1) begin
            Integer depth = index == 0 ? 1 : (index == 1 ? 8 : 17);
            Bit#(16) last = fromInteger(depth - 1);
            Bit#(16) invalid = fromInteger(depth);

            dynamicAssert(validLocalResponse(localTag(LocalActivation, 0), LocalActivation, 1, depth),
                          "zero local response row rejected");
            dynamicAssert(validLocalResponse(localTag(LocalActivation, last), LocalActivation, 1, depth),
                          "last local response row rejected");
            dynamicAssert(!validLocalResponse(localTag(LocalActivation, invalid), LocalActivation, 1, depth),
                          "out-of-range local response row accepted");
            dynamicAssert(validMetadataResponse(localTag(LocalHp1Meta, 0), depth),
                          "zero metadata response row rejected");
            dynamicAssert(validMetadataResponse(localTag(LocalHp1Meta, last), depth),
                          "last metadata response row rejected");
            dynamicAssert(!validMetadataResponse(localTag(LocalHp1Meta, invalid), depth),
                          "out-of-range metadata response row accepted");
            dynamicAssert(storeWorkValid(storeWorkAt(0), 1, depth),
                          "zero accumulator store row rejected");
            dynamicAssert(storeWorkValid(storeWorkAt(last), 1, depth),
                          "last accumulator store row rejected");
            dynamicAssert(!storeWorkValid(storeWorkAt(invalid), 1, depth),
                          "out-of-range accumulator store row accepted");
        end
        step <= 1;
    endrule

    rule writeScratchFirst(step == 1
                           && scratch1.writeReady
                           && scratch8.writeReady
                           && scratch17.writeReady);
        scratch1.write(0, replicate(True), intRow(11));
        scratch8.write(0, replicate(True), intRow(21));
        scratch17.write(0, replicate(True), intRow(31));
        step <= 2;
    endrule

    rule writeScratchLast(step == 2 && scratch8.writeReady && scratch17.writeReady);
        scratch8.write(7, replicate(True), intRow(22));
        scratch17.write(16, replicate(True), intRow(32));
        step <= 3;
    endrule

    rule requestScratchFirst(step == 3
                             && scratch1.readReady
                             && scratch8.readReady
                             && scratch17.readReady);
        scratch1.requestRead(0);
        scratch8.requestRead(0);
        scratch17.requestRead(0);
        step <= 4;
    endrule

    rule checkScratchFirst(step == 4
                           && scratch1.readValid
                           && scratch8.readValid
                           && scratch17.readValid);
        dynamicAssert(scratch1.readData == intRow(11), "depth-one scratchpad mismatch");
        dynamicAssert(scratch8.readData == intRow(21), "scratchpad first row aliased");
        dynamicAssert(scratch17.readData == intRow(31), "scratchpad first row aliased");
        scratch1.consumeRead;
        scratch8.consumeRead;
        scratch17.consumeRead;
        step <= 5;
    endrule

    rule requestScratchLast(step == 5 && scratch8.readReady && scratch17.readReady);
        scratch8.requestRead(7);
        scratch17.requestRead(16);
        step <= 6;
    endrule

    rule checkScratchLast(step == 6 && scratch8.readValid && scratch17.readValid);
        dynamicAssert(scratch8.readData == intRow(22), "scratchpad last row mismatch");
        dynamicAssert(scratch17.readData == intRow(32), "scratchpad last row mismatch");
        scratch8.consumeRead;
        scratch17.consumeRead;
        step <= 7;
    endrule

    rule writeHp1First(step == 7);
        hp1.writeBlockScales(0, replicate(True), blockRow(1));
        hp1.writeRowShifts(0, replicate(True), shiftRow(2));
        hp8.writeBlockScales(0, replicate(True), blockRow(3));
        hp8.writeRowShifts(0, replicate(True), shiftRow(5));
        hp17.writeBlockScales(0, replicate(True), blockRow(7));
        hp17.writeRowShifts(0, replicate(True), shiftRow(9));
        step <= 8;
    endrule

    rule writeHp1Last(step == 8);
        hp8.writeBlockScales(7, replicate(True), blockRow(4));
        hp8.writeRowShifts(7, replicate(True), shiftRow(6));
        hp17.writeBlockScales(16, replicate(True), blockRow(8));
        hp17.writeRowShifts(16, replicate(True), shiftRow(10));
        step <= 9;
    endrule

    rule checkHp1(step == 9);
        dynamicAssert(hp1.readBlockScales(0) == blockRow(1), "depth-one HP1 block mismatch");
        dynamicAssert(hp1.readRowShifts(0) == shiftRow(2), "depth-one HP1 row mismatch");
        dynamicAssert(hp8.readBlockScales(0) == blockRow(3), "HP1 block first row aliased");
        dynamicAssert(hp8.readBlockScales(7) == blockRow(4), "HP1 block last row mismatch");
        dynamicAssert(hp8.readRowShifts(0) == shiftRow(5), "HP1 row first row aliased");
        dynamicAssert(hp8.readRowShifts(7) == shiftRow(6), "HP1 row last row mismatch");
        dynamicAssert(hp17.readBlockScales(0) == blockRow(7), "HP1 block first row aliased");
        dynamicAssert(hp17.readBlockScales(16) == blockRow(8), "HP1 block last row mismatch");
        dynamicAssert(hp17.readRowShifts(0) == shiftRow(9), "HP1 row first row aliased");
        dynamicAssert(hp17.readRowShifts(16) == shiftRow(10), "HP1 row last row mismatch");
        step <= 10;
    endrule

    rule writeAccumulatorFirst(step == 10
                               && accumulator1.writeReady
                               && accumulator8.writeReady
                               && accumulator17.writeReady);
        accumulator1.write(0, 0, False, 41);
        accumulator8.write(0, 0, False, 51);
        accumulator17.write(0, 0, False, 61);
        step <= 11;
    endrule

    rule completeAccumulatorFirst(step == 11
                                  && accumulator1.writeCompleteValid
                                  && accumulator8.writeCompleteValid
                                  && accumulator17.writeCompleteValid);
        dynamicAssert(accumulator1.writeComplete.row == 0, "depth-one completion row mismatch");
        dynamicAssert(accumulator8.writeComplete.row == 0, "accumulator first completion row mismatch");
        dynamicAssert(accumulator17.writeComplete.row == 0, "accumulator first completion row mismatch");
        accumulator1.consumeWriteComplete;
        accumulator8.consumeWriteComplete;
        accumulator17.consumeWriteComplete;
        step <= 12;
    endrule

    rule writeAccumulatorLast(step == 12 && accumulator8.writeReady && accumulator17.writeReady);
        accumulator8.write(0, 7, False, 52);
        accumulator17.write(0, 16, False, 62);
        step <= 13;
    endrule

    rule completeAccumulatorLast(step == 13
                                 && accumulator8.writeCompleteValid
                                 && accumulator17.writeCompleteValid);
        dynamicAssert(accumulator8.writeComplete.row == 7, "accumulator last completion row mismatch");
        dynamicAssert(accumulator17.writeComplete.row == 16, "accumulator last completion row mismatch");
        accumulator8.consumeWriteComplete;
        accumulator17.consumeWriteComplete;
        step <= 14;
    endrule

    rule requestAccumulatorFirst(step == 14
                                 && accumulator1.readReady
                                 && accumulator8.readReady
                                 && accumulator17.readReady);
        accumulator1.requestRead(0, 0);
        accumulator8.requestRead(0, 0);
        accumulator17.requestRead(0, 0);
        step <= 15;
    endrule

    rule checkAccumulatorFirst(step == 15
                               && accumulator1.readValid
                               && accumulator8.readValid
                               && accumulator17.readValid);
        dynamicAssert(accumulator1.readResponse.value == 41, "depth-one accumulator mismatch");
        dynamicAssert(accumulator8.readResponse.value == 51, "accumulator first row aliased");
        dynamicAssert(accumulator17.readResponse.value == 61, "accumulator first row aliased");
        accumulator1.consumeRead;
        accumulator8.consumeRead;
        accumulator17.consumeRead;
        step <= 16;
    endrule

    rule requestAccumulatorLast(step == 16
                                && accumulator8.readReady
                                && accumulator17.readReady);
        accumulator8.requestRead(0, 7);
        accumulator17.requestRead(0, 16);
        step <= 17;
    endrule

    rule checkAccumulatorLast(step == 17
                              && accumulator8.readValid
                              && accumulator17.readValid);
        dynamicAssert(accumulator8.readResponse.value == 52, "accumulator last row mismatch");
        dynamicAssert(accumulator17.readResponse.value == 62, "accumulator last row mismatch");
        accumulator8.consumeRead;
        accumulator17.consumeRead;
        $display("PASS: mkTbMemoryDepth");
        $finish(0);
    endrule
endmodule

endpackage
