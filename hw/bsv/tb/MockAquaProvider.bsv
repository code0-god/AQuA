package MockAquaProvider;

import Assert::*;
import FIFOF::*;
import SpecialFIFOs::*;

interface MockProviderPipeIfc#(type payload_t);
    method Bool acceptReady;
    method Action accept(payload_t payload);
    method Bool responseValid;
    method payload_t response;
    method Action consume;
endinterface

module mkMockProviderPipe#(Integer latency)(
    MockProviderPipeIfc#(payload_t)
) provisos (Bits#(payload_t, payloadWidth));
    FIFOF#(payload_t) responses <- mkBypassFIFOF;
    Reg#(Maybe#(payload_t)) delayed <- mkReg(tagged Invalid);
    Reg#(UInt#(16)) remaining <- mkReg(0);

    staticAssert(latency >= 0, "mock provider latency must be nonnegative");

    rule advanceDelayed(
        isValid(delayed)
        && responses.notFull
    );
        if (remaining == 1) begin
            responses.enq(fromMaybe(?, delayed));
            delayed <= tagged Invalid;
            remaining <= 0;
        end
        else begin
            remaining <= remaining - 1;
        end
    endrule

    method Bool acceptReady = !isValid(delayed);

    method Action accept(payload_t payload) if (!isValid(delayed));
        delayed <= tagged Valid payload;
        remaining <= fromInteger(latency == 0 ? 1 : latency);
    endmethod

    method Bool responseValid = responses.notEmpty;

    method payload_t response if (responses.notEmpty);
        return responses.first;
    endmethod

    method Action consume if (responses.notEmpty);
        responses.deq;
    endmethod
endmodule

endpackage
