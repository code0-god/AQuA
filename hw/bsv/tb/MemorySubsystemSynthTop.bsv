package MemorySubsystemSynthTop;

import AquaMemorySubsystem::*;
import AquaMemorySubsystemTypes::*;

(* synthesize *)
module mkMemorySubsystemSynthTop(Empty);
    AquaMemorySubsystemIfc#(16, 2, 16, 16, 8, 8, 6, 8, 32)
        subsystem <- mkAquaMemorySubsystem;
endmodule

endpackage
