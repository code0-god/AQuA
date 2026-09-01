package TbAquaMemorySubsystem;

import Assert::*;
import AccumulatorMem::*;
import AquaLocalAddr::*;
import AquaMemorySubsystem::*;
import AquaMemorySubsystemTypes::*;
import AquaMemoryTypes::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import Hp1MetaMem::*;
import MockAquaProvider::*;
import ScratchpadBank::*;
import Vector::*;

typedef ScratchpadRowPayload#(16, Int#(8)) ActivationPayload;
typedef ScratchpadRowPayload#(16, Bit#(8)) WeightPayload;
typedef AquaMemoryReadResponse#(ActivationPayload) ActivationResponse;
typedef AquaMemoryReadResponse#(WeightPayload) WeightResponse;
typedef AquaMemoryReadResponse#(Hp1BlockScale#(6)) BlockResponse;
typedef AquaMemoryReadResponse#(UInt#(6)) RowResponse;

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

function ProviderLoadWork#(16) integrationLoad;
    return ProviderLoadWork {
        jobId: 14,
        stripeId: 2,
        macroTileId: 4,
        arrayWorkId: 8,
        fragmentId: 16,
        activationTensor: 1001,
        weightTensor: 1002,
        iStart: 4,
        iCount: 2,
        jStart: 8,
        jCount: 2,
        fragmentKStart: 24,
        fragmentKCount: 8,
        fragmentBlockIndex: 0,
        activationBase: localAddress(LocalActivation, 1),
        weightBase: localAddress(LocalWeight, 4),
        blockShiftDestination: localAddress(LocalHp1Meta, 7),
        rowScaleDestination: localAddress(LocalHp1Meta, 8)
    };
endfunction

function StoreWork#(16) integrationStore;
    return StoreWork {
        jobId: 14,
        stripeId: 2,
        macroTileId: 4,
        arrayWorkId: 8,
        outputTensor: 1003,
        iStart: 4,
        iCount: 1,
        jStart: 8,
        jCount: 2,
        accumulatorBase: localAddress(LocalAccumulator, 0)
    };
endfunction

(* descending_urgency = "requestActivation, dut_load_issueActivation, requestWeight, dut_load_issueWeight, requestBlock, dut_load_issueBlockShift, requestRow, dut_load_issueRowScale" *)
module mkTbAquaMemorySubsystem(Empty);
    AquaMemorySubsystemIfc#(16, 2, 16, 16, 8, 8, 6, 8, 32) dut
        <- mkAquaMemorySubsystem;

    MockProviderPipeIfc#(WeightResponse) weightPipe
        <- mkMockProviderPipe(1);
    MockProviderPipeIfc#(BlockResponse) blockPipe
        <- mkMockProviderPipe(3);

    Reg#(UInt#(3)) accumulatorInitIssued <- mkReg(0);
    Reg#(UInt#(3)) accumulatorInitDone <- mkReg(0);
    Reg#(Bool) started <- mkReg(False);
    Reg#(UInt#(3)) outputCount <- mkReg(0);
    Reg#(Maybe#(AquaMemoryTag)) pendingOutputAck
        <- mkReg(tagged Invalid);
    Reg#(Bool) loadDone <- mkReg(False);
    Reg#(Bool) storeDone <- mkReg(False);
    Reg#(UInt#(3)) verifyStep <- mkReg(0);
    Reg#(UInt#(16)) cycles <- mkReg(0);
    Reg#(UInt#(8)) activationRequestsSeen <- mkReg(0);
    Reg#(UInt#(8)) weightRequestsSeen <- mkReg(0);
    Reg#(UInt#(8)) blockRequestsSeen <- mkReg(0);
    Reg#(UInt#(8)) rowRequestsSeen <- mkReg(0);
    Reg#(UInt#(8)) weightResponsesSeen <- mkReg(0);
    Reg#(UInt#(8)) blockResponsesSeen <- mkReg(0);

    rule initializeAccumulator(
        accumulatorInitIssued < 2
        && accumulatorInitIssued == accumulatorInitDone
        && dut.accumulator.writeReady
    );
        dut.accumulator.write(
            zeroExtend(pack(accumulatorInitIssued)),
            0,
            False,
            500 + signExtend(unpack(pack(accumulatorInitIssued)))
        );
        accumulatorInitIssued <= accumulatorInitIssued + 1;
    endrule

    rule completeAccumulatorInitialization(
        dut.accumulator.writeCompleteValid
        && accumulatorInitDone < 2
    );
        dut.accumulator.consumeWriteComplete;
        accumulatorInitDone <= accumulatorInitDone + 1;
    endrule

    rule startBoth(
        accumulatorInitDone == 2
        && !started
        && dut.loadReady
        && dut.storeReady
    );
        dut.scheduleLoad(integrationLoad);
        dut.scheduleStore(integrationStore);
        started <= True;
    endrule

    rule requestActivation(
        dut.activationRequestValid
    );
        let request = dut.activationRequest;
        Vector#(16, Int#(8)) data =
            replicate(unpack(truncate(pack(request.outer.start))));
        Vector#(16, Bool) mask = replicate(False);
        for (Integer lane = 0; lane < 8; lane = lane + 1) begin
            mask[lane] = True;
        end
        ActivationResponse response = AquaMemoryReadResponse {
            tag: request.tag,
            payload: ScratchpadRowPayload { mask: mask, data: data }
        };
        dynamicAssert(dut.queuedActivationResponseReady(response),
                      "same-cycle activation response not ready");
        dut.putQueuedActivationResponse(response);
        activationRequestsSeen <= activationRequestsSeen + 1;
    endrule

    rule requestWeight(
        dut.weightRequestValid
        && weightPipe.acceptReady
        && !weightPipe.responseValid
    );
        let request = dut.weightRequest;
        Vector#(16, Bit#(8)) data =
            replicate(truncate(pack(request.outer.start)));
        Vector#(16, Bool) mask = replicate(False);
        for (Integer lane = 0; lane < 8; lane = lane + 1) begin
            mask[lane] = True;
        end
        weightPipe.accept(AquaMemoryReadResponse {
            tag: request.tag,
            payload: ScratchpadRowPayload { mask: mask, data: data }
        });
        dut.consumeWeightRequest;
        weightRequestsSeen <= weightRequestsSeen + 1;
    endrule

    rule requestBlock(
        dut.blockShiftRequestValid
        && blockPipe.acceptReady
        && !blockPipe.responseValid
    );
        let request = dut.blockShiftRequest;
        blockPipe.accept(AquaMemoryReadResponse {
            tag: request.tag,
            payload: Hp1BlockScale {
                zeroBlock: False,
                leftShift: 3
            }
        });
        dut.consumeBlockShiftRequest;
        blockRequestsSeen <= blockRequestsSeen + 1;
    endrule

    rule requestRow(
        dut.rowScaleRequestValid
    );
        let request = dut.rowScaleRequest;
        RowResponse response = AquaMemoryReadResponse {
            tag: request.tag,
            payload: 5
        };
        dynamicAssert(dut.queuedRowScaleResponseReady(response),
                      "same-cycle row response not ready");
        dut.putQueuedRowScaleResponse(response);
        rowRequestsSeen <= rowRequestsSeen + 1;
    endrule

    rule respondWeight(
        weightPipe.responseValid
        && dut.weightResponseReady(weightPipe.response)
    );
        dut.putWeightResponse(weightPipe.response);
        weightPipe.consume;
        weightResponsesSeen <= weightResponsesSeen + 1;
    endrule

    rule respondBlock(
        blockPipe.responseValid
        && dut.blockShiftResponseReady(blockPipe.response)
    );
        dut.putBlockShiftResponse(blockPipe.response);
        blockPipe.consume;
        blockResponsesSeen <= blockResponsesSeen + 1;
    endrule


    rule acknowledgeOutput(dut.outputRequestValid);
        let request = dut.outputRequest;
        dynamicAssert(request.outputColumn.start == 8 + zeroExtend(outputCount),
                      "subsystem output J mismatch");
        dynamicAssert(request.rawValue == 500 + signExtend(unpack(pack(outputCount))),
                      "subsystem raw output mismatch");
        dut.consumeOutputRequest;
        pendingOutputAck <= tagged Valid request.tag;
        outputCount <= outputCount + 1;
    endrule

    rule sendOutputAck(
        isValid(pendingOutputAck)
        && dut.outputAckReady(AquaMemoryWriteAck {
            tag: fromMaybe(?, pendingOutputAck),
            accepted: True
        })
    );
        dut.putOutputAck(AquaMemoryWriteAck {
            tag: fromMaybe(?, pendingOutputAck),
            accepted: True
        });
        pendingOutputAck <= tagged Invalid;
    endrule

    rule captureLoadCompletion(dut.loadCompletionValid);
        let block = dut.hp1Meta.readBlockScale(7);
        let row = dut.hp1Meta.readRowShift(8);
        dynamicAssert(!block.zeroBlock && block.leftShift == 3,
                      "block metadata was not staged");
        dynamicAssert(row == 5, "row metadata was not staged");
        dut.consumeLoadCompletion;
        loadDone <= True;
    endrule

    rule captureStoreCompletion(dut.storeCompletionValid);
        dynamicAssert(outputCount == 2,
                      "subsystem store completed before final ack");
        dut.consumeStoreCompletion;
        storeDone <= True;
    endrule

    rule requestActivationBank0(loadDone && verifyStep == 0);
        dut.activationBanks[0].requestRead(1);
        verifyStep <= 1;
    endrule

    rule verifyActivationBank0(
        verifyStep == 1
        && dut.activationBanks[0].readValid
    );
        dynamicAssert(dut.activationBanks[0].readData[0] == 4,
                      "activation bank zero write mismatch");
        dut.activationBanks[0].consumeRead;
        dut.activationBanks[1].requestRead(1);
        verifyStep <= 2;
    endrule

    rule verifyActivationBank1(
        verifyStep == 2
        && dut.activationBanks[1].readValid
    );
        dynamicAssert(dut.activationBanks[1].readData[7] == 5,
                      "activation bank one write mismatch");
        dut.activationBanks[1].consumeRead;
        dut.weightBanks[0].requestRead(4);
        verifyStep <= 3;
    endrule

    rule verifyWeightBank0(
        verifyStep == 3
        && dut.weightBanks[0].readValid
    );
        dynamicAssert(dut.weightBanks[0].readData[0] == 8,
                      "weight bank zero write mismatch");
        dut.weightBanks[0].consumeRead;
        dut.weightBanks[1].requestRead(4);
        verifyStep <= 4;
    endrule

    rule verifyWeightBank1(
        verifyStep == 4
        && dut.weightBanks[1].readValid
    );
        dynamicAssert(dut.weightBanks[1].readData[7] == 9,
                      "weight bank one write mismatch");
        dut.weightBanks[1].consumeRead;
        verifyStep <= 5;
    endrule

    rule finish(storeDone && verifyStep == 5);
        $display("PASS mkTbAquaMemorySubsystem");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 500) begin
            $display(
                "WATCHDOG load=%0d store=%0d verify=%0d A=%0d W=%0d/%0d/%0d/%0d B=%0d/%0d/%0d/%0d R=%0d",
                loadDone,
                storeDone,
                verifyStep,
                activationRequestsSeen,
                weightRequestsSeen,
                weightResponsesSeen,
                weightPipe.responseValid,
                weightPipe.responseValid
                    && dut.weightResponseReady(weightPipe.response),
                blockRequestsSeen,
                blockResponsesSeen,
                blockPipe.responseValid,
                blockPipe.responseValid
                    && dut.blockShiftResponseReady(blockPipe.response),
                rowRequestsSeen
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
