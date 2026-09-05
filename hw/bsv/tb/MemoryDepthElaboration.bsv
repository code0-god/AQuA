package MemoryDepthElaboration;

import AccumulatorMem::*;
import Hp1MetaMem::*;
import Scratchpad::*;

module mkScratchpadZeroDepth(Empty);
    ScratchpadBankIfc#(0, 1, Bit#(8)) memory <- mkScratchpadBank;
endmodule

module mkHp1BlockZeroDepth(Empty);
    Hp1MetaMemIfc#(0, 1, 1, 4, 4) memory <- mkHp1MetaMem;
endmodule

module mkHp1RowZeroDepth(Empty);
    Hp1MetaMemIfc#(1, 0, 1, 4, 4) memory <- mkHp1MetaMem;
endmodule

module mkAccumulatorZeroDepth(Empty);
    AccumulatorMemIfc#(1, 0, 8) memory <- mkAccumulatorMem;
endmodule

endpackage
