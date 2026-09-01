package Hp1MetaMem;

import Assert::*;
import AquaTypes::*;
import RegFile::*;

typedef Bit#(TLog#(TAdd#(entries, 1))) Hp1MetaAddr#(numeric type entries);

interface Hp1MetaMemIfc#(
    numeric type entries,
    numeric type shiftWidth
);
    method Action writeBlockScale(
        Hp1MetaAddr#(entries) address,
        Hp1BlockScale#(shiftWidth) scale
    );
    method Hp1BlockScale#(shiftWidth) readBlockScale(
        Hp1MetaAddr#(entries) address
    );
    method Action writeRowShift(
        Hp1MetaAddr#(entries) address,
        UInt#(shiftWidth) shift
    );
    method UInt#(shiftWidth) readRowShift(
        Hp1MetaAddr#(entries) address
    );
endinterface

module mkHp1MetaMem(Hp1MetaMemIfc#(entries, shiftWidth));
    RegFile#(
        Hp1MetaAddr#(entries),
        Hp1BlockScale#(shiftWidth)
    ) blockScales <- mkRegFileFull;
    RegFile#(
        Hp1MetaAddr#(entries),
        UInt#(shiftWidth)
    ) rowShifts <- mkRegFileFull;

    method Action writeBlockScale(
        Hp1MetaAddr#(entries) address,
        Hp1BlockScale#(shiftWidth) scale
    );
        dynamicAssert(address < fromInteger(valueOf(entries)), "HP1 block metadata out of range");
        blockScales.upd(address, scale);
    endmethod

    method Hp1BlockScale#(shiftWidth) readBlockScale(
        Hp1MetaAddr#(entries) address
    );
        if (address >= fromInteger(valueOf(entries))) begin
            return error("HP1 block metadata out of range");
        end
        else begin
            return blockScales.sub(address);
        end
    endmethod

    method Action writeRowShift(
        Hp1MetaAddr#(entries) address,
        UInt#(shiftWidth) shift
    );
        dynamicAssert(address < fromInteger(valueOf(entries)), "HP1 row metadata out of range");
        rowShifts.upd(address, shift);
    endmethod

    method UInt#(shiftWidth) readRowShift(
        Hp1MetaAddr#(entries) address
    );
        if (address >= fromInteger(valueOf(entries))) begin
            return error("HP1 row metadata out of range");
        end
        else begin
            return rowShifts.sub(address);
        end
    endmethod
endmodule

endpackage
