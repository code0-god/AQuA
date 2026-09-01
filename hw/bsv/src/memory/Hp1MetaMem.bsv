package Hp1MetaMem;

import Assert::*;
import AquaTypes::*;
import RegFile::*;
import Vector::*;

typedef Bit#(TLog#(TAdd#(entries, 1))) Hp1MetaAddr#(numeric type entries);

interface Hp1MetaMemIfc#(
    numeric type entries,
    numeric type lanes,
    numeric type shiftWidth
);
    method Action writeBlockScales(
        Hp1MetaAddr#(entries) address,
        Vector#(lanes, Bool) mask,
        Vector#(lanes, Hp1BlockScale#(shiftWidth)) scales
    );
    method Vector#(lanes, Hp1BlockScale#(shiftWidth)) readBlockScales(
        Hp1MetaAddr#(entries) address
    );
    method Action writeRowShifts(
        Hp1MetaAddr#(entries) address,
        Vector#(lanes, Bool) mask,
        Vector#(lanes, UInt#(shiftWidth)) shifts
    );
    method Vector#(lanes, UInt#(shiftWidth)) readRowShifts(
        Hp1MetaAddr#(entries) address
    );
endinterface

module mkHp1MetaMem(Hp1MetaMemIfc#(entries, lanes, shiftWidth));
    Vector#(
        lanes,
        RegFile#(Hp1MetaAddr#(entries), Hp1BlockScale#(shiftWidth))
    ) blockScales <- replicateM(mkRegFileFull);
    Vector#(
        lanes,
        RegFile#(Hp1MetaAddr#(entries), UInt#(shiftWidth))
    ) rowShifts <- replicateM(mkRegFileFull);

    method Action writeBlockScales(
        Hp1MetaAddr#(entries) address,
        Vector#(lanes, Bool) mask,
        Vector#(lanes, Hp1BlockScale#(shiftWidth)) scales
    );
        dynamicAssert(address < fromInteger(valueOf(entries)),
                      "HP1 block metadata out of range");
        for (Integer lane = 0; lane < valueOf(lanes); lane = lane + 1) begin
            if (mask[lane]) begin
                blockScales[lane].upd(address, scales[lane]);
            end
        end
    endmethod

    method Vector#(lanes, Hp1BlockScale#(shiftWidth)) readBlockScales(
        Hp1MetaAddr#(entries) address
    );
        if (address >= fromInteger(valueOf(entries))) begin
            return error("HP1 block metadata out of range");
        end
        else begin
            Vector#(lanes, Hp1BlockScale#(shiftWidth)) scales = replicate(?);
            for (Integer lane = 0; lane < valueOf(lanes); lane = lane + 1) begin
                scales[lane] = blockScales[lane].sub(address);
            end
            return scales;
        end
    endmethod

    method Action writeRowShifts(
        Hp1MetaAddr#(entries) address,
        Vector#(lanes, Bool) mask,
        Vector#(lanes, UInt#(shiftWidth)) shifts
    );
        dynamicAssert(address < fromInteger(valueOf(entries)),
                      "HP1 row metadata out of range");
        for (Integer lane = 0; lane < valueOf(lanes); lane = lane + 1) begin
            if (mask[lane]) begin
                rowShifts[lane].upd(address, shifts[lane]);
            end
        end
    endmethod

    method Vector#(lanes, UInt#(shiftWidth)) readRowShifts(
        Hp1MetaAddr#(entries) address
    );
        if (address >= fromInteger(valueOf(entries))) begin
            return error("HP1 row metadata out of range");
        end
        else begin
            Vector#(lanes, UInt#(shiftWidth)) shifts = replicate(?);
            for (Integer lane = 0; lane < valueOf(lanes); lane = lane + 1) begin
                shifts[lane] = rowShifts[lane].sub(address);
            end
            return shifts;
        end
    endmethod
endmodule

endpackage
