package LoadChannel;

import Assert::*;
import AquaMemoryTypes::*;
import FIFOF::*;

interface LoadRequestSourceIfc;
    method Bool requestValid;
    method AquaMemoryReadRequest request;
    method Action consumeRequest;
endinterface

interface LoadChannelIfc#(numeric type arrayDim);
    interface LoadRequestSourceIfc requests;
    method Bool issueReady;
    method Action issue(
        Bit#(TLog#(arrayDim)) lane,
        AquaMemoryReadRequest request
    );
    method Bool isPending(Bit#(TLog#(arrayDim)) lane);
    method Bool queuedTagMatches(AquaMemoryTag tag);
    method Action complete(Bit#(TLog#(arrayDim)) lane);
    method Action completeQueued(Bit#(TLog#(arrayDim)) lane);
    method Bool empty;
endinterface

module mkLoadChannel(LoadChannelIfc#(arrayDim))
    provisos (
        Add#(laneTagPadding, TLog#(arrayDim), 40)
    );
    FIFOF#(AquaMemoryReadRequest) requestQueue <- mkFIFOF;
    Reg#(Bit#(arrayDim)) reserved <- mkReg(0);
    Reg#(Bit#(arrayDim)) pending <- mkReg(0);
    Reg#(Maybe#(AquaMemoryTag)) queuedTag <- mkReg(tagged Invalid);
    interface LoadRequestSourceIfc requests;
        method Bool requestValid = requestQueue.notEmpty;
        method AquaMemoryReadRequest request if (requestQueue.notEmpty);
            return requestQueue.first;
        endmethod
        method Action consumeRequest if (requestQueue.notEmpty);
            Bit#(TLog#(arrayDim)) lane =
                truncate(pack(requestQueue.first.tag.transactionId));
            dynamicAssert(reserved[lane] == 1,
                          "consumed load request is not reserved");
            dynamicAssert(
                isValid(queuedTag)
                && fromMaybe(?, queuedTag) == requestQueue.first.tag,
                "consumed load request tag mismatch"
            );
            Bit#(arrayDim) nextReserved = reserved;
            nextReserved[lane] = 0;
            reserved <= nextReserved;
            Bit#(arrayDim) nextPending = pending;
            nextPending[lane] = 1;
            pending <= nextPending;
            queuedTag <= tagged Invalid;
            requestQueue.deq;
        endmethod
    endinterface

    method Bool issueReady =
        requestQueue.notFull
        && reserved == 0
        && pending == 0;

    method Action issue(
        Bit#(TLog#(arrayDim)) lane,
        AquaMemoryReadRequest request
    ) if (
        requestQueue.notFull
        && reserved == 0
        && pending == 0
    );
        dynamicAssert(reserved[lane] == 0,
                      "load channel lane already reserved");
        dynamicAssert(pending[lane] == 0,
                      "load channel lane already pending");
        Bit#(arrayDim) nextReserved = reserved;
        nextReserved[lane] = 1;
        reserved <= nextReserved;
        queuedTag <= tagged Valid request.tag;
        requestQueue.enq(request);
    endmethod

    method Bool isPending(Bit#(TLog#(arrayDim)) lane);
        return pending[lane] == 1;
    endmethod

    method Bool queuedTagMatches(AquaMemoryTag tag);
        return isValid(queuedTag) && fromMaybe(?, queuedTag) == tag;
    endmethod

    method Action complete(Bit#(TLog#(arrayDim)) lane);
        dynamicAssert(pending[lane] == 1,
                      "load response lane is not pending");
        Bit#(arrayDim) nextPending = pending;
        nextPending[lane] = 0;
        pending <= nextPending;
    endmethod

    method Action completeQueued(Bit#(TLog#(arrayDim)) lane)
        if (requestQueue.notEmpty);
        dynamicAssert(reserved[lane] == 1,
                      "same-cycle load request is not reserved");
        dynamicAssert(
                      truncate(pack(
                          requestQueue.first.tag.transactionId
                      )) == lane,
                      "same-cycle load response lane mismatch");
        Bit#(arrayDim) nextReserved = reserved;
        nextReserved[lane] = 0;
        reserved <= nextReserved;
        queuedTag <= tagged Invalid;
        requestQueue.deq;
    endmethod

    method Bool empty =
        !requestQueue.notEmpty
        && !isValid(queuedTag)
        && reserved == 0
        && pending == 0;
endmodule

endpackage
