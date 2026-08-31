package TbMetadataResponseMaskMismatch;

import AquaLocalAddr::*;
import AquaMemorySubsystem::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import Vector::*;

function AquaLocalAddr localAddress(
    AquaLocalRegion region,
    Bit#(16) row
);
    return AquaLocalAddr { region: region, bank: 0, row: row };
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
        jCount: 3,
        fragmentKStart: 0,
        fragmentKCount: 8,
        fragmentBlockIndex: 0,
        activationBase: localAddress(LocalActivation, 0),
        weightBase: localAddress(LocalWeight, 0),
        blockShiftDestination: localAddress(LocalHp1Meta, 0),
        rowScaleDestination: localAddress(LocalHp1Meta, 1)
    };
endfunction

(* synthesize *)
module mkTbMetadataResponseMaskMismatch(Empty);
    AquaMemorySubsystemIfc#(
        16,
        2, 16,
        3, 17,
        16,
        8, 8, 6,
        5, 8, 32
    ) dut <- mkAquaMemorySubsystem;
    Reg#(Bool) started <- mkReg(False);

    rule start(!started && dut.loadReady);
        dut.scheduleLoad(loadWork);
        started <= True;
    endrule

    rule sendShortBlockMask(dut.blockShiftPort.requests.valid);
        let request = dut.blockShiftPort.requests.first;
        Vector#(16, Bool) mask = replicate(False);
        mask[0] = True;
        mask[1] = True;
        Vector#(16, Hp1BlockScale#(6)) data = replicate(
            Hp1BlockScale { zeroBlock: False, leftShift: 1 }
        );
        BlockShiftMemoryResponse#(16, 6) response = AquaMemoryReadResponse {
            tag: request.tag,
            payload: ScratchpadRowPayload { mask: mask, data: data }
        };

        // Expected assertion for later Makefile registration:
        // metadata response mask does not match requested J count
        dut.blockShiftPort.requests.consume;
        dut.blockShiftPort.responses.put(response);
    endrule
endmodule

endpackage
