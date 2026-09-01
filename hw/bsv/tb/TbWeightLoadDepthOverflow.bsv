package TbWeightLoadDepthOverflow;

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

function ProviderLoadWork#(16) loadWork;
    return ProviderLoadWork {
        jobId: 1,
        stripeId: 2,
        arrayWorkId: 3,
        fragmentId: 4,
        activationTensor: 5,
        weightTensor: 6,
        iStart: 0,
        iCount: 1,
        jStart: 0,
        jCount: 2,
        fragmentKStart: 0,
        fragmentKCount: 8,
        fragmentBlockIndex: 0,
        activationBase: localAddress(LocalActivation, 0, 0),
        weightBase: localAddress(LocalWeight, 2, 16),
        blockShiftDestination: localAddress(LocalHp1Meta, 0, 0),
        rowScaleDestination: localAddress(LocalHp1Meta, 0, 1)
    };
endfunction

(* synthesize *)
module mkTbWeightLoadDepthOverflow(Empty);
    AquaMemorySubsystemIfc#(
        16,
        2, 16,
        3, 17,
        16,
        8, 8, 6,
        5, 8, 32
    ) dut <- mkAquaMemorySubsystem;

    rule scheduleOutOfBounds(dut.loadReady);
        dut.scheduleLoad(loadWork);
        $display("out-of-depth weight work unexpectedly accepted");
        $finish(1);
    endrule
endmodule

endpackage
