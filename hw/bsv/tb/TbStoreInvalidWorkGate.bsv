package TbStoreInvalidWorkGate;

import AccumulatorMem::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaWorkTypes::*;
import StoreController::*;

function StoreWork#(16) invalidWork;
    return StoreWork {
        jobId: 1,
        stripeId: 2,
        arrayWorkId: 3,
        outputTensor: 4,
        iStart: 0,
        iCount: 1,
        jStart: 0,
        jCount: 2,
        accumulatorBase: AquaLocalAddr {
            region: LocalAccumulator,
            bank: 1,
            row: 0
        }
    };
endfunction

(* synthesize *)
module mkTbStoreInvalidWorkGate(Empty);
    AccumulatorMemIfc#(2, 2, 32) accumulator <- mkAccumulatorMem;
    StoreControllerIfc#(16, 2, 2, 32) dut
        <- mkStoreController(accumulator);
    Reg#(UInt#(2)) step <- mkReg(0);

    rule scheduleInvalid(step == 0 && dut.startReady);
        dut.start(invalidWork);
        step <= 1;
    endrule

    rule verifyRejected(step == 1);
        if (dut.startReady && !dut.outputPort.requests.valid) begin
            $display("PASS mkTbStoreInvalidWorkGate");
            $finish(0);
        end
        else begin
            $display("FAIL invalid store work entered active state");
            $finish(1);
        end
    endrule
endmodule

endpackage
