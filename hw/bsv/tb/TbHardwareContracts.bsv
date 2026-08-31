package TbHardwareContracts;

import Assert::*;
import AquaTypes::*;

(* synthesize *)
module mkTbHardwareContracts(Empty);
    staticAssert(valueOf(AquaBlockSize) == 32, "AQuA block size mismatch");
    staticAssert(valueOf(SizeOf#(MatrixExtent)) == 32, "matrix extent width mismatch");
    staticAssert(valueOf(SizeOf#(MatmulJobId)) == 32, "job ID width mismatch");
    staticAssert(valueOf(SizeOf#(StripeId)) == 32, "stripe ID width mismatch");

    rule verify;
        dynamicAssert(aquaBlockSize == 32, "runtime block size mismatch");
        $display("PASS mkTbHardwareContracts");
        $finish(0);
    endrule
endmodule

endpackage
