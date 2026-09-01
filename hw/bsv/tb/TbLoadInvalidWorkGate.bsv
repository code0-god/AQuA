package TbLoadInvalidWorkGate;

import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaMemorySubsystem::*;
import AquaTypes::*;
import AquaWorkTypes::*;

function AquaLocalAddr localAddress(
    AquaLocalRegion region,
    Bit#(8) bank,
    Bit#(16) row
);
    return AquaLocalAddr { region: region, bank: bank, row: row };
endfunction

function ProviderLoadWork#(16) invalidWork;
    return ProviderLoadWork {
        jobId: 1,
        stripeId: 2,
        arrayWorkId: 3,
        fragmentId: 4,
        activationTensor: 5,
        weightTensor: 6,
        iStart: 0,
        iCount: 2,
        jStart: 0,
        jCount: 1,
        fragmentKStart: 0,
        fragmentKCount: 8,
        fragmentBlockIndex: 0,
        activationBase: localAddress(LocalActivation, 1, 15),
        weightBase: localAddress(LocalWeight, 0, 0),
        blockShiftDestination: localAddress(LocalHp1Meta, 0, 0),
        rowScaleDestination: localAddress(LocalHp1Meta, 0, 1)
    };
endfunction

(* synthesize *)
module mkTbLoadInvalidWorkGate(Empty);
    AquaMemorySubsystemIfc#(
        16,
        2, 16,
        3, 17,
        16,
        8, 8, 6,
        5, 8, 32
    ) dut <- mkAquaMemorySubsystem;
    Reg#(UInt#(2)) step <- mkReg(0);

    rule scheduleInvalid(step == 0 && dut.loadReady);
        dut.scheduleLoad(invalidWork);
        step <= 1;
    endrule

    rule verifyRejected(step == 1);
        Bool noRequests =
            !dut.activationPort.requests.valid
            && !dut.weightPort.requests.valid
            && !dut.blockShiftPort.requests.valid
            && !dut.rowShiftPort.requests.valid;
        if (dut.loadReady && noRequests) begin
            $display("PASS mkTbLoadInvalidWorkGate");
            $finish(0);
        end
        else begin
            $display("FAIL invalid load work entered active state");
            $finish(1);
        end
    endrule
endmodule

endpackage
