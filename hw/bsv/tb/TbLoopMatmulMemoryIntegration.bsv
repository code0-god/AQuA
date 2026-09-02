package TbLoopMatmulMemoryIntegration;

import Assert::*;
import AccumulatorMem::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaMemorySubsystem::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import AquaLoopMatmul::*;
import Hp1MetaMem::*;
import MockAquaProvider::*;
import Scratchpad::*;
import Vector::*;

typedef ScratchpadRowPayload#(16, Int#(8)) ActivationPayload;
typedef ScratchpadRowPayload#(16, Bit#(8)) WeightPayload;
typedef AquaMemoryReadResponse#(ActivationPayload) ActivationResponse;
typedef AquaMemoryReadResponse#(WeightPayload) WeightResponse;
typedef BlockShiftMemoryResponse#(16, 6) BlockResponse;
typedef RowScaleMemoryResponse#(16, 6) RowResponse;

function AquaMatmulDescriptor descriptor;
    return AquaMatmulDescriptor {
        jobId: 80,
        mode: FullMatrix,
        m: 2,
        n: 2,
        k: 80,
        stripeRows: 2,
        macroNTileColumns: 2,
        macroKTileElements: 32,
        activationTensor: 1001,
        weightTensor: 1002,
        outputTensor: 1003,
        jobContext: 1004
    };
endfunction

(* descending_urgency = "requestActivation, memory_load_issueActivation, requestWeight, memory_load_issueWeight, requestBlock, memory_load_issueBlockShift, requestRow, memory_load_issueRowShift" *)
module mkTbLoopMatmulMemoryIntegration(Empty);
    AquaLoopMatmulIfc#(16) loop <- mkAquaLoopMatmul;
    AquaMemorySubsystemIfc#(
        16,
        2, 16,
        3, 17,
        16, 16,
        8, 8,
        6, 6,
        16, 8, 32
    ) memory <- mkAquaMemorySubsystem;

    MockProviderPipeIfc#(ActivationResponse) activationPipe
        <- mkMockProviderPipe(0);
    MockProviderPipeIfc#(WeightResponse) weightPipe
        <- mkMockProviderPipe(1);
    MockProviderPipeIfc#(BlockResponse) blockPipe
        <- mkMockProviderPipe(3);
    MockProviderPipeIfc#(RowResponse) rowPipe
        <- mkMockProviderPipe(0);

    Reg#(Bool) started <- mkReg(False);
    Reg#(UInt#(16)) cycles <- mkReg(0);
    Reg#(UInt#(4)) loadsCompleted <- mkReg(0);
    Reg#(UInt#(2)) storesScheduled <- mkReg(0);
    Reg#(UInt#(3)) outputCount <- mkReg(0);
    Reg#(Maybe#(AquaMemoryTag)) pendingOutputAck
        <- mkReg(tagged Invalid);
    Reg#(Maybe#(ExecuteWork#(16))) activeExecute
        <- mkReg(tagged Invalid);
    Reg#(ArrayCount) executeI <- mkReg(0);
    Reg#(ArrayCount) executeJ <- mkReg(0);
    Reg#(Bool) writePending <- mkReg(False);
    Reg#(UInt#(4)) fragmentsCompleted <- mkReg(0);
    Reg#(Bool) stripeDone <- mkReg(False);

    rule start(!started && loop.startReady);
        loop.start(descriptor);
        started <= True;
    endrule

    rule scheduleLoad(
        loop.loadWorkValid
        && memory.loadReady
    );
        memory.scheduleLoad(loop.loadWork);
        loop.consumeLoadWork;
    endrule

    rule completeLoad(
        memory.loadCompletionValid
        && loop.loadCompletionReady(memory.loadCompletion)
    );
        loop.putLoadCompletion(memory.loadCompletion);
        memory.consumeLoadCompletion;
        loadsCompleted <= loadsCompleted + 1;
    endrule

    rule acceptExecute(
        loop.executeWorkValid
        && !isValid(activeExecute)
    );
        let work = loop.executeWork;
        ArrayWorkId expectedArrayWorkId = 2;
        if (fragmentsCompleted < 2) begin
            expectedArrayWorkId = 0;
        end
        else if (fragmentsCompleted < 4) begin
            expectedArrayWorkId = 1;
        end
        KFragmentId expectedFragmentId =
            fragmentsCompleted == 1 || fragmentsCompleted == 3
            ? 1
            : 0;
        dynamicAssert(work.iCount == 2, "executor I count");
        dynamicAssert(work.jCount == 2, "executor J count");
        dynamicAssert(
            work.fragmentKStart == zeroExtend(fragmentsCompleted) * 16,
            "executor K start"
        );
        dynamicAssert(work.fragmentKCount == 16, "executor K count");
        dynamicAssert(
            work.arrayWorkId == expectedArrayWorkId,
            "executor array work ID"
        );
        dynamicAssert(
            work.fragmentId == expectedFragmentId,
            "executor fragment ID"
        );
        dynamicAssert(
            work.accumulate == (fragmentsCompleted != 0),
            "executor accumulation mode"
        );
        loop.consumeExecuteWork;
        activeExecute <= tagged Valid work;
        executeI <= 0;
        executeJ <= 0;
    endrule

    rule writeContribution(
        isValid(activeExecute)
        && !writePending
        && memory.accumulator.writeReady
    );
        let work = fromMaybe(?, activeExecute);
        UInt#(32) baseBank =
            zeroExtend(unpack(work.accumulatorBase.bank));
        UInt#(32) baseRow =
            zeroExtend(unpack(work.accumulatorBase.row));
        UInt#(32) localI = zeroExtend(executeI);
        UInt#(32) localJ = zeroExtend(executeJ);
        AccumulatorBank#(16) bank =
            truncate(pack(baseBank + localJ));
        AccumulatorRow#(8) row =
            truncate(pack(baseRow + localI));
        memory.accumulator.write(
            bank,
            row,
            work.accumulate,
            1
        );
        writePending <= True;
    endrule

    rule completeContribution(
        isValid(activeExecute)
        && writePending
        && memory.accumulator.writeCompleteValid
    );
        let work = fromMaybe(?, activeExecute);
        UInt#(32) baseBank =
            zeroExtend(unpack(work.accumulatorBase.bank));
        UInt#(32) baseRow =
            zeroExtend(unpack(work.accumulatorBase.row));
        UInt#(32) localI = zeroExtend(executeI);
        UInt#(32) localJ = zeroExtend(executeJ);
        AccumulatorBank#(16) expectedBank =
            truncate(pack(baseBank + localJ));
        AccumulatorRow#(8) expectedRow =
            truncate(pack(baseRow + localI));
        dynamicAssert(
            memory.accumulator.writeComplete.bank == expectedBank,
            "executor write completion bank"
        );
        dynamicAssert(
            memory.accumulator.writeComplete.row == expectedRow,
            "executor write completion row"
        );
        memory.accumulator.consumeWriteComplete;
        writePending <= False;

        if (executeJ + 1 < work.jCount) begin
            executeJ <= executeJ + 1;
        end
        else if (executeI + 1 < work.iCount) begin
            executeI <= executeI + 1;
            executeJ <= 0;
        end
        else begin
            loop.putExecuteCompletion(ExecuteCompletion {
                jobId: work.jobId,
                stripeId: work.stripeId,
                arrayWorkId: work.arrayWorkId,
                fragmentId: work.fragmentId
            });
            activeExecute <= tagged Invalid;
            fragmentsCompleted <= fragmentsCompleted + 1;
        end
    endrule

    rule scheduleStore(
        loop.storeWorkValid
        && memory.storeReady
    );
        memory.scheduleStore(loop.storeWork);
        loop.consumeStoreWork;
        storesScheduled <= storesScheduled + 1;
    endrule

    rule completeStore(
        memory.storeCompletionValid
        && loop.storeCompletionReady(memory.storeCompletion)
    );
        dynamicAssert(
            outputCount == 4,
            "store completed before four output acknowledgements"
        );
        loop.putStoreCompletion(memory.storeCompletion);
        memory.consumeStoreCompletion;
    endrule

    rule requestActivation(
        memory.activationPort.requests.valid
        && activationPipe.acceptReady
        && !activationPipe.responseValid
    );
        let request = memory.activationPort.requests.first;
        Vector#(16, Int#(8)) data = replicate(1);
        Vector#(16, Bool) mask = replicate(True);
        activationPipe.accept(AquaMemoryReadResponse {
            tag: request.tag,
            payload: ScratchpadRowPayload { mask: mask, data: data }
        });
        memory.activationPort.requests.consume;
    endrule

    rule requestWeight(
        memory.weightPort.requests.valid
        && weightPipe.acceptReady
        && !weightPipe.responseValid
    );
        let request = memory.weightPort.requests.first;
        Vector#(16, Bit#(8)) data = replicate(1);
        Vector#(16, Bool) mask = replicate(True);
        weightPipe.accept(AquaMemoryReadResponse {
            tag: request.tag,
            payload: ScratchpadRowPayload { mask: mask, data: data }
        });
        memory.weightPort.requests.consume;
    endrule

    rule requestBlock(
        memory.blockShiftPort.requests.valid
        && blockPipe.acceptReady
        && !blockPipe.responseValid
    );
        let request = memory.blockShiftPort.requests.first;
        Vector#(16, Bool) mask = replicate(False);
        mask[0] = True;
        mask[1] = True;
        Vector#(16, Hp1BlockScale#(6)) data = replicate(?);
        data[0] = Hp1BlockScale {
            zeroBlock: False,
            leftShift: 0
        };
        data[1] = Hp1BlockScale {
            zeroBlock: False,
            leftShift: 0
        };
        blockPipe.accept(AquaMemoryReadResponse {
            tag: request.tag,
            payload: ScratchpadRowPayload { mask: mask, data: data }
        });
        memory.blockShiftPort.requests.consume;
    endrule

    rule requestRow(
        memory.rowShiftPort.requests.valid
        && rowPipe.acceptReady
        && !rowPipe.responseValid
    );
        let request = memory.rowShiftPort.requests.first;
        Vector#(16, Bool) mask = replicate(False);
        mask[0] = True;
        mask[1] = True;
        Vector#(16, UInt#(6)) data = replicate(0);
        rowPipe.accept(AquaMemoryReadResponse {
            tag: request.tag,
            payload: ScratchpadRowPayload { mask: mask, data: data }
        });
        memory.rowShiftPort.requests.consume;
    endrule

    rule respondActivation(
        activationPipe.responseValid
        && memory.activationPort.responses.ready(
            activationPipe.response
        )
    );
        memory.activationPort.responses.put(activationPipe.response);
        activationPipe.consume;
    endrule

    rule respondWeight(
        weightPipe.responseValid
        && memory.weightPort.responses.ready(weightPipe.response)
    );
        memory.weightPort.responses.put(weightPipe.response);
        weightPipe.consume;
    endrule

    rule respondBlock(
        blockPipe.responseValid
        && memory.blockShiftPort.responses.ready(blockPipe.response)
    );
        memory.blockShiftPort.responses.put(blockPipe.response);
        blockPipe.consume;
    endrule

    rule respondRow(
        rowPipe.responseValid
        && memory.rowShiftPort.responses.ready(rowPipe.response)
    );
        memory.rowShiftPort.responses.put(rowPipe.response);
        rowPipe.consume;
    endrule

    rule captureOutput(
        memory.outputPort.requests.valid
        && !isValid(pendingOutputAck)
    );
        let request = memory.outputPort.requests.first;
        UInt#(3) expectedRow = outputCount / 2;
        UInt#(3) expectedColumn = outputCount % 2;
        dynamicAssert(
            request.outputRow.start == zeroExtend(expectedRow),
            "output row order"
        );
        dynamicAssert(
            request.outputColumn.start == zeroExtend(expectedColumn),
            "output column order"
        );
        dynamicAssert(request.rawValue == 5, "output raw value");
        memory.outputPort.requests.consume;
        pendingOutputAck <= tagged Valid request.tag;
        outputCount <= outputCount + 1;
    endrule

    rule acknowledgeOutput(
        isValid(pendingOutputAck)
        && memory.outputPort.responses.ready(AquaMemoryWriteAck {
            tag: fromMaybe(?, pendingOutputAck),
            accepted: True
        })
    );
        memory.outputPort.responses.put(AquaMemoryWriteAck {
            tag: fromMaybe(?, pendingOutputAck),
            accepted: True
        });
        pendingOutputAck <= tagged Invalid;
    endrule

    rule consumeStripeCompletion(
        loop.stripeCompletionValid
        && !stripeDone
    );
        dynamicAssert(
            fragmentsCompleted == 5,
            "stripe completed before five fragments"
        );
        dynamicAssert(
            loadsCompleted == 5,
            "stripe completed before five loads"
        );
        dynamicAssert(
            storesScheduled == 1,
            "store was not final-macro-K only"
        );
        dynamicAssert(
            outputCount == 4 && !isValid(pendingOutputAck),
            "stripe completed before output acknowledgements"
        );
        loop.consumeStripeCompletion;
        stripeDone <= True;
    endrule

    rule finish(stripeDone && loop.startReady);
        dynamicAssert(
            !memory.storeCompletionValid,
            "memory store completion remained pending"
        );
        $display("PASS mkTbLoopMatmulMemoryIntegration");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 500) begin
            $display(
                "WATCHDOG phase=%0d loads=%0d stores=%0d outputs=%0d fragments=%0d",
                loop.debugPhase,
                loadsCompleted,
                storesScheduled,
                outputCount,
                fragmentsCompleted
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
