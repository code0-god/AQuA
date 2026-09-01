package TbInvalidAccumulatorBankGeometry;

import AquaMemorySubsystem::*;

(* synthesize *)
module mkTbInvalidAccumulatorBankGeometry(Empty);
    AquaMemorySubsystemIfc#(
        16,
        1, 1,
        1, 1,
        1, 1,
        8, 8,
        5, 4,
        8, 1, 32
    ) dut <- mkAquaMemorySubsystem;

    rule unexpectedSuccess;
        $display("FAIL invalid accumulator bank geometry elaborated");
        $finish(1);
    endrule
endmodule

endpackage
