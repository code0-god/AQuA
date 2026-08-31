package TbStoreController;

import Assert::*;
import AccumulatorMem::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import StoreController::*;

function StoreWork#(16) storeWork;
    AquaLocalAddr accumulatorBase = AquaLocalAddr {
        region: LocalAccumulator,
        bank: 0,
        row: 0
    };
    return StoreWork {
        jobId: 9,
        stripeId: 4,
        arrayWorkId: 12,
        outputTensor: 303,
        iStart: 20,
        iCount: 2,
        jStart: 30,
        jCount: 3,
        accumulatorBase: accumulatorBase
    };
endfunction

module mkTbStoreController(Empty);
    AccumulatorMemIfc#(16, 8, 32) accumulator <- mkAccumulatorMem;
    StoreControllerIfc#(16, 16, 8, 32) dut
        <- mkStoreController(accumulator);

    Reg#(UInt#(4)) initIssued <- mkReg(0);
    Reg#(UInt#(4)) initCompleted <- mkReg(0);
    Reg#(Bool) started <- mkReg(False);
    Reg#(UInt#(4)) outputIndex <- mkReg(0);
    Reg#(UInt#(4)) firstWriteStall <- mkReg(0);
    Reg#(Maybe#(AquaMemoryTag)) pendingProviderAck
        <- mkReg(tagged Invalid);
    Reg#(UInt#(3)) firstAckStall <- mkReg(0);
    Reg#(UInt#(16)) cycles <- mkReg(0);

    rule initializeAccumulator(
        initIssued < 6
        && initIssued == initCompleted
        && accumulator.writeReady
    );
        UInt#(4) localI = initIssued / 3;
        UInt#(4) localJ = initIssued % 3;
        accumulator.write(
            zeroExtend(pack(localJ)),
            truncate(pack(localI)),
            False,
            100 + signExtend(unpack(pack(initIssued)))
        );
        initIssued <= initIssued + 1;
    endrule

    rule completeInitialization(
        accumulator.writeCompleteValid
        && initCompleted < 6
    );
        accumulator.consumeWriteComplete;
        initCompleted <= initCompleted + 1;
    endrule

    rule startStore(
        initCompleted == 6
        && !started
        && dut.startReady
    );
        dut.start(storeWork);
        started <= True;
    endrule

    rule holdFirstWrite(
        started
        && outputIndex == 0
        && dut.outputPort.requests.valid
        && firstWriteStall < 3
    );
        let request = dut.outputPort.requests.first;
        dynamicAssert(request.rawValue == 100,
                      "stalled output payload changed");
        dynamicAssert(request.outputRow.start == 20,
                      "stalled output row changed");
        dynamicAssert(request.outputColumn.start == 30,
                      "stalled output column changed");
        dynamicAssert(
            !dut.outputPort.responses.ready(AquaMemoryWriteAck {
                tag: request.tag,
                accepted: True
            }),
            "store accepted acknowledgement before request consumption"
        );
        firstWriteStall <= firstWriteStall + 1;
    endrule

    rule consumeOutput(
        started
        && dut.outputPort.requests.valid
        && !(outputIndex == 0 && firstWriteStall < 3)
    );
        let request = dut.outputPort.requests.first;
        MatrixExtent localI = zeroExtend(outputIndex / 3);
        MatrixExtent localJ = zeroExtend(outputIndex % 3);
        dynamicAssert(request.tag.jobId == 9,
                      "output request job mismatch");
        dynamicAssert(request.tag.stripeId == 4,
                      "output request stripe mismatch");
        dynamicAssert(request.tag.arrayWorkId == 12,
                      "output request array work mismatch");
        dynamicAssert(request.tensorId == 303,
                      "output tensor mismatch");
        dynamicAssert(request.outputRow.start == 20 + localI,
                      "output row traversal mismatch");
        dynamicAssert(request.outputColumn.start == 30 + localJ,
                      "output J traversal mismatch");
        dynamicAssert(request.outputRow.count == 1,
                      "output row count mismatch");
        dynamicAssert(request.outputColumn.count == 1,
                      "output J count mismatch");
        dynamicAssert(
            request.rawValue
                == 100 + signExtend(unpack(pack(outputIndex))),
            "raw accumulator value changed"
        );
        dut.outputPort.requests.consume;
        pendingProviderAck <= tagged Valid request.tag;
        outputIndex <= outputIndex + 1;
    endrule

    rule stallFirstAck(
        isValid(pendingProviderAck)
        && outputIndex == 1
        && firstAckStall < 2
    );
        dynamicAssert(!dut.outputPort.requests.valid,
                      "store advanced before output acknowledgement");
        firstAckStall <= firstAckStall + 1;
    endrule

    rule acknowledgeOutput(
        isValid(pendingProviderAck)
        && !(outputIndex == 1 && firstAckStall < 2)
        && dut.outputPort.responses.ready(AquaMemoryWriteAck {
            tag: fromMaybe(?, pendingProviderAck),
            accepted: True
        })
    );
        dut.outputPort.responses.put(AquaMemoryWriteAck {
            tag: fromMaybe(?, pendingProviderAck),
            accepted: True
        });
        pendingProviderAck <= tagged Invalid;
    endrule

    rule finish(started && dut.completionValid);
        let completion = dut.completion;
        dynamicAssert(outputIndex == 6,
                      "store completed before final acknowledgement");
        dynamicAssert(completion.jobId == 9,
                      "store completion job mismatch");
        dynamicAssert(completion.arrayWorkId == 12,
                      "store completion array work mismatch");
        dut.consumeCompletion;
        $display("PASS mkTbStoreController");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 300) begin
            $display(
                "WATCHDOG init=%0d output=%0d",
                initCompleted,
                outputIndex
            );
            $finish(1);
        end
    endrule
endmodule

endpackage
