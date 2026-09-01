package ActivationSpad;

import ScratchpadBank::*;
import Vector::*;

interface ActivationSpadIfc#(
    numeric type banks,
    numeric type rowsPerBank,
    numeric type lanes,
    type element_t
);
    interface Vector#(
        banks,
        ScratchpadBankIfc#(rowsPerBank, lanes, element_t)
    ) banks;
endinterface

module mkActivationSpad(
    ActivationSpadIfc#(banks, rowsPerBank, lanes, element_t)
) provisos (Bits#(element_t, elementWidth));
    Vector#(
        banks,
        ScratchpadBankIfc#(rowsPerBank, lanes, element_t)
    ) bankVector <- replicateM(mkScratchpadBank);

    interface banks = bankVector;
endmodule

endpackage
