package TbWorkRangeOverflowGate;

import AquaTypes::*;
import AquaWorkTypes::*;
import WorkScheduler::*;

function ArrayWork#(16) invalidWork;
    return ArrayWork {
        jobId: 1,
        stripeId: 2,
        iStart: 0,
        jStart: 0,
        iCount: 1,
        jCount: 1,
        kTileStart: 32'hfffffff0,
        kTileCount: 32
    };
endfunction

(* synthesize *)
module mkTbWorkRangeOverflowGate(Empty);
    WorkSchedulerIfc#(16) dut <- mkWorkScheduler;
    Reg#(UInt#(2)) step <- mkReg(0);

    rule scheduleInvalid(step == 0 && dut.startReady);
        dut.start(invalidWork, False);
        step <= 1;
    endrule

    rule verifyRejected(step == 1);
        if (
            dut.startReady
            && !dut.fragmentValid
            && !dut.lookaheadValid
            && !dut.doneValid
        ) begin
            $display("PASS mkTbWorkRangeOverflowGate");
            $finish(0);
        end
        else begin
            $display("FAIL overflowing work entered scheduler state");
            $finish(1);
        end
    endrule
endmodule

endpackage
