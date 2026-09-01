package TbAccumulatorBankGeometry;

import AquaMemorySubsystem::*;

(* synthesize *)
module mkTbAccumulatorBankGeometry(Empty);
    AquaMemorySubsystemIfc#(
        16,
        1, 1,
        1, 1,
        1, 1,
        8, 8,
        5, 4,
        16, 1, 32
    ) dim16 <- mkAquaMemorySubsystem;
    AquaMemorySubsystemIfc#(
        32,
        1, 1,
        1, 1,
        1, 1,
        8, 8,
        5, 4,
        32, 1, 32
    ) dim32 <- mkAquaMemorySubsystem;
    AquaMemorySubsystemIfc#(
        64,
        1, 1,
        1, 1,
        1, 1,
        8, 8,
        5, 4,
        64, 1, 32
    ) dim64 <- mkAquaMemorySubsystem;

    rule finish;
        $display("PASS mkTbAccumulatorBankGeometry");
        $finish(0);
    endrule
endmodule

endpackage
