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

    if (latency > 0) begin
        rule advanceDelayed (
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
    end

    method Bool acceptReady =
        latency == 0
            ? responses.notFull
            : !isValid(delayed);

    method Action accept(payload_t payload)
        if (
            (latency == 0 && responses.notFull)
            || (latency > 0 && !isValid(delayed))
        );
        if (latency == 0) begin
            responses.enq(payload);
        end
        else begin
            delayed <= tagged Valid payload;
            remaining <= fromInteger(latency);
        end
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
