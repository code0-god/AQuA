package TbMockAquaProvider;

import Assert::*;
import MockAquaProvider::*;

module mkTbMockAquaProvider(Empty);
    MockProviderPipeIfc#(UInt#(16)) sameCycle
        <- mkMockProviderPipe(0);
    MockProviderPipeIfc#(UInt#(16)) oneCycle
        <- mkMockProviderPipe(1);
    MockProviderPipeIfc#(UInt#(16)) fixedLatency
        <- mkMockProviderPipe(3);

    Reg#(Bool) offered <- mkReg(False);
    Reg#(Maybe#(UInt#(16))) sameSeen <- mkReg(tagged Invalid);
    Reg#(Maybe#(UInt#(16))) oneSeen <- mkReg(tagged Invalid);
    Reg#(Maybe#(UInt#(16))) fixedSeen <- mkReg(tagged Invalid);
    Reg#(UInt#(4)) fixedStall <- mkReg(0);
    Reg#(UInt#(16)) cycles <- mkReg(0);

    rule offer(
        !offered
        && sameCycle.acceptReady
        && oneCycle.acceptReady
        && fixedLatency.acceptReady
    );
        sameCycle.accept(10);
        oneCycle.accept(20);
        fixedLatency.accept(30);
        offered <= True;
    endrule

    rule consumeSame(!isValid(sameSeen) && sameCycle.responseValid);
        dynamicAssert(sameCycle.response == 10,
                      "same-cycle provider payload mismatch");
        sameCycle.consume;
        sameSeen <= tagged Valid cycles;
    endrule

    rule consumeOne(!isValid(oneSeen) && oneCycle.responseValid);
        dynamicAssert(oneCycle.response == 20,
                      "one-cycle provider payload mismatch");
        oneCycle.consume;
        oneSeen <= tagged Valid cycles;
    endrule

    rule stallFixed(
        !isValid(fixedSeen)
        && fixedLatency.responseValid
        && fixedStall < 2
    );
        dynamicAssert(fixedLatency.response == 30,
                      "backpressured provider payload changed");
        fixedStall <= fixedStall + 1;
    endrule

    rule consumeFixed(
        !isValid(fixedSeen)
        && fixedLatency.responseValid
        && fixedStall == 2
    );
        dynamicAssert(fixedLatency.response == 30,
                      "fixed-latency provider payload mismatch");
        fixedLatency.consume;
        fixedSeen <= tagged Valid cycles;
    endrule

    rule finish(
        isValid(sameSeen)
        && isValid(oneSeen)
        && isValid(fixedSeen)
    );
        dynamicAssert(fromMaybe(?, sameSeen) == 1,
                      "zero-latency provider exposed response in request cycle");
        dynamicAssert(fromMaybe(?, oneSeen) == 1,
                      "one-cycle response latency mismatch");
        dynamicAssert(fromMaybe(?, fixedSeen) == 5,
                      "fixed response/backpressure timing mismatch");
        $display("PASS mkTbMockAquaProvider");
        $finish(0);
    endrule

    rule watchdog;
        cycles <= cycles + 1;
        if (cycles == 100) begin
            $display("WATCHDOG mock provider");
            $finish(1);
        end
    endrule
endmodule

endpackage
