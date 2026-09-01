package TbActivationResponseMaskMismatch;

import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaMemorySubsystem::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import Vector::*;

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
        jCount: 1,
        fragmentKStart: 0,
        fragmentKCount: 8,
        fragmentBlockIndex: 0,
        activationBase: localAddress(LocalActivation, 0, 0),
        weightBase: localAddress(LocalWeight, 0, 0),
        blockShiftDestination: localAddress(LocalHp1Meta, 0, 0),
        rowScaleDestination: localAddress(LocalHp1Meta, 0, 1)
    };
endfunction

(* synthesize *)
module mkTbActivationResponseMaskMismatch(Empty);
    AquaMemorySubsystemIfc#(
        16,
        2, 16,
        3, 17,
        16,
        8, 8, 6,
        5, 8, 32
    ) dut <- mkAquaMemorySubsystem;
    Reg#(Bool) started <- mkReg(False);
    Reg#(Maybe#(AquaMemoryTag)) pending <- mkReg(tagged Invalid);

    rule start(!started && dut.loadReady);
        dut.scheduleLoad(loadWork);
        started <= True;
    endrule

    rule consumeRequest(
        dut.activationPort.requests.valid
        && !isValid(pending)
    );
        pending <= tagged Valid dut.activationPort.requests.first.tag;
        dut.activationPort.requests.consume;
    endrule

    rule sendShortMask(isValid(pending));
        Vector#(16, Bool) mask = replicate(False);
        Vector#(16, Int#(8)) data = replicate(1);
        for (Integer lane = 0; lane < 7; lane = lane + 1) begin
            mask[lane] = True;
        end
        ActivationMemoryResponse#(16, 8) response =
            AquaMemoryReadResponse {
                tag: fromMaybe(?, pending),
                payload: ScratchpadRowPayload { mask: mask, data: data }
            };

        dut.activationPort.responses.put(response);
        $display("activation response mask unexpectedly accepted");
        $finish(1);
    endrule
endmodule

endpackage
