package MemorySubsystemSynthTop;

import AquaMemorySubsystem::*;

(* synthesize *)
module mkMemorySubsystemSynthTop(Empty);
    AquaMemorySubsystemIfc#(
        16,
        2, 16,
        4, 32,
        24, 12,
        8, 8,
        5, 4,
        8, 12, 32
    ) subsystem <- mkAquaMemorySubsystem;
endmodule

endpackage
