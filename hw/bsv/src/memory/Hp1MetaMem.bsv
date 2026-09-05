package Hp1MetaMem;

import Assert::*;
import AquaTypes::*;
import RegFile::*;
import Vector::*;

typedef Bit#(TLog#(TAdd#(blockEntries, 1))) Hp1BlockMetaAddr#(
    numeric type blockEntries
);
typedef Bit#(TLog#(TAdd#(rowEntries, 1))) Hp1RowMetaAddr#(
    numeric type rowEntries
);

interface Hp1MetaMemIfc#(
    numeric type blockEntries,
    numeric type rowEntries,
    numeric type lanes,
    numeric type blockShiftWidth,
    numeric type rowShiftWidth
);
    method Action writeBlockScales(
        Hp1BlockMetaAddr#(blockEntries) address,
        Vector#(lanes, Bool) mask,
        Vector#(lanes, Hp1BlockScale#(blockShiftWidth)) scales
    );
    method Vector#(lanes, Hp1BlockScale#(blockShiftWidth)) readBlockScales(
        Hp1BlockMetaAddr#(blockEntries) address
    );
    method Action writeRowShifts(
        Hp1RowMetaAddr#(rowEntries) address,
        Vector#(lanes, Bool) mask,
        Vector#(lanes, UInt#(rowShiftWidth)) shifts
    );
    method Vector#(lanes, UInt#(rowShiftWidth)) readRowShifts(
        Hp1RowMetaAddr#(rowEntries) address
    );
endinterface

module mkHp1MetaMem(Hp1MetaMemIfc#(
    blockEntries,
    rowEntries,
    lanes,
    blockShiftWidth,
    rowShiftWidth
));
    staticAssert(valueOf(blockEntries) > 0, "HP1 block entries must be positive");
    staticAssert(valueOf(rowEntries) > 0, "HP1 row entries must be positive");
    Vector#(
        lanes,
        RegFile#(
            Hp1BlockMetaAddr#(blockEntries),
            Hp1BlockScale#(blockShiftWidth)
        )
    ) blockScales <- replicateM(mkRegFile(0, fromInteger(valueOf(blockEntries) - 1)));
    Vector#(
        lanes,
        RegFile#(Hp1RowMetaAddr#(rowEntries), UInt#(rowShiftWidth))
    ) rowShifts <- replicateM(mkRegFile(0, fromInteger(valueOf(rowEntries) - 1)));

    method Action writeBlockScales(
        Hp1BlockMetaAddr#(blockEntries) address,
        Vector#(lanes, Bool) mask,
        Vector#(lanes, Hp1BlockScale#(blockShiftWidth)) scales
    );
        dynamicAssert(address < fromInteger(valueOf(blockEntries)),
                      "HP1 block metadata out of range");
        for (Integer lane = 0; lane < valueOf(lanes); lane = lane + 1) begin
            if (mask[lane]) begin
                blockScales[lane].upd(address, scales[lane]);
            end
        end
    endmethod

    method Vector#(lanes, Hp1BlockScale#(blockShiftWidth)) readBlockScales(
        Hp1BlockMetaAddr#(blockEntries) address
    );
        if (address >= fromInteger(valueOf(blockEntries))) begin
            return error("HP1 block metadata out of range");
        end
        else begin
            Vector#(
                lanes,
                Hp1BlockScale#(blockShiftWidth)
            ) scales = replicate(?);
            for (Integer lane = 0; lane < valueOf(lanes); lane = lane + 1) begin
                scales[lane] = blockScales[lane].sub(address);
            end
            return scales;
        end
    endmethod

    method Action writeRowShifts(
        Hp1RowMetaAddr#(rowEntries) address,
        Vector#(lanes, Bool) mask,
        Vector#(lanes, UInt#(rowShiftWidth)) shifts
    );
        dynamicAssert(address < fromInteger(valueOf(rowEntries)),
                      "HP1 row metadata out of range");
        for (Integer lane = 0; lane < valueOf(lanes); lane = lane + 1) begin
            if (mask[lane]) begin
                rowShifts[lane].upd(address, shifts[lane]);
            end
        end
    endmethod

    method Vector#(lanes, UInt#(rowShiftWidth)) readRowShifts(
        Hp1RowMetaAddr#(rowEntries) address
    );
        if (address >= fromInteger(valueOf(rowEntries))) begin
            return error("HP1 row metadata out of range");
        end
        else begin
            Vector#(lanes, UInt#(rowShiftWidth)) shifts = replicate(?);
            for (Integer lane = 0; lane < valueOf(lanes); lane = lane + 1) begin
                shifts[lane] = rowShifts[lane].sub(address);
            end
            return shifts;
        end
    endmethod
endmodule

endpackage
