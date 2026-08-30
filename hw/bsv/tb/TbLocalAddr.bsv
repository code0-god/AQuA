package TbLocalAddr;

import Assert::*;
import AquaLocalAddr::*;

(* synthesize *)
module mkTbLocalAddr(Empty);
    rule verify;
        AquaLocalAddr#(2, 2, 4) address = AquaLocalAddr {
            region: LocalWeight,
            slot: 1,
            bank: 2,
            row: 7
        };
        AquaBankedRow#(2, 4) mapped = mapGlobalRow(7, 4);

        dynamicAssert(address.region == LocalWeight, "region mismatch");
        dynamicAssert(address.slot == 1, "slot mismatch");
        dynamicAssert(address.bank == 2, "bank mismatch");
        dynamicAssert(address.row == 7, "row mismatch");
        dynamicAssert(mapped.bank == 3, "global row bank mismatch");
        dynamicAssert(mapped.row == 1, "global row local row mismatch");

        $display("PASS mkTbLocalAddr");
        $finish(0);
    endrule
endmodule

endpackage
