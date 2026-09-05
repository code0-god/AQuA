package TbMemoryAddressWidth;

import AccumulatorMem::*;
import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import Hp1MetaMem::*;
import LoadStager::*;
import Scratchpad::*;
import StoreController::*;

(* synthesize *)
module mkTbMemoryAddressWidth(Empty);
    staticAssert(valueOf(SizeOf#(ScratchpadRowAddr#(1))) == 1
        && valueOf(SizeOf#(ScratchpadRowAddr#(8))) == 3
        && valueOf(SizeOf#(ScratchpadRowAddr#(17))) == 5
        && valueOf(SizeOf#(ScratchpadRowAddr#(65536))) == 16,
        "scratchpad address width must address depth entries");
    staticAssert(valueOf(SizeOf#(Hp1BlockMetaAddr#(1))) == 1
        && valueOf(SizeOf#(Hp1BlockMetaAddr#(8))) == 3
        && valueOf(SizeOf#(Hp1BlockMetaAddr#(17))) == 5
        && valueOf(SizeOf#(Hp1BlockMetaAddr#(65536))) == 16,
        "HP1 block address width must address depth entries");
    staticAssert(valueOf(SizeOf#(Hp1RowMetaAddr#(1))) == 1
        && valueOf(SizeOf#(Hp1RowMetaAddr#(8))) == 3
        && valueOf(SizeOf#(Hp1RowMetaAddr#(17))) == 5
        && valueOf(SizeOf#(Hp1RowMetaAddr#(65536))) == 16,
        "HP1 row address width must address depth entries");
    staticAssert(valueOf(SizeOf#(AccumulatorRow#(1))) == 1
        && valueOf(SizeOf#(AccumulatorRow#(8))) == 3
        && valueOf(SizeOf#(AccumulatorRow#(17))) == 5
        && valueOf(SizeOf#(AccumulatorRow#(65536))) == 16,
        "accumulator address width must address depth entries");
    staticAssert(valueOf(SizeOf#(AccumulatorBank#(1))) == 1
        && valueOf(SizeOf#(AccumulatorBank#(16))) == 4
        && valueOf(SizeOf#(AccumulatorBank#(256))) == 8,
        "accumulator bank width must address bank count");

    rule checkBoundary;
        Bit#(16) last = 65535;
        AquaMemoryTag tag = AquaMemoryTag {
            jobId: 0, stripeId: 0, arrayWorkId: 0, fragmentId: 0,
            transactionId: 0,
            localAddress: AquaLocalAddr { region: LocalActivation, bank: 0, row: last }
        };
        dynamicAssert(validLocalResponse(tag, LocalActivation, 1, 65536),
                      "last local row rejected at maximum depth");
        tag.localAddress.region = LocalHp1Meta;
        dynamicAssert(validMetadataResponse(tag, 65536),
                      "last metadata row rejected at maximum depth");

        StoreWork#(16) work = StoreWork {
            jobId: 0, stripeId: 0, arrayWorkId: 0, outputTensor: 0,
            iStart: 0, iCount: 1, jStart: 0, jCount: 1,
            accumulatorBase: AquaLocalAddr {
                region: LocalAccumulator, bank: 15, row: last
            }
        };
        dynamicAssert(storeWorkValid(work, 16, 65536),
                      "store of row 65535 rejected");
        work.iCount = 2;
        dynamicAssert(!storeWorkValid(work, 16, 65536),
                      "store spanning invalid row 65536 accepted");
        $display("PASS: mkTbMemoryAddressWidth");
        $finish(0);
    endrule
endmodule

endpackage
