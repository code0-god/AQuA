package AquaMemoryAddressing;

import AquaLocalAddr::*;
import AquaWorkTypes::*;

function DefaultAquaLocalAddr offsetBankedAddress(
    DefaultAquaLocalAddr base,
    UInt#(32) offset,
    Integer bankCount
);
    if (bankCount <= 0) begin
        return error("bank count must be positive");
    end
    else begin
        UInt#(32) baseBank = zeroExtend(unpack(base.bank));
        UInt#(40) linear =
            zeroExtend(unpack(base.row)) * fromInteger(bankCount)
            + zeroExtend(baseBank)
            + zeroExtend(offset);
        UInt#(40) bank = linear % fromInteger(bankCount);
        UInt#(40) row = linear / fromInteger(bankCount);
        // Controller boundary assertions prove bank and row fit before this
        // pure address derivation is used.
        return DefaultAquaLocalAddr {
            region: base.region,
            slot: base.slot,
            bank: truncate(pack(bank)),
            row: truncate(pack(row))
        };
    end
endfunction

endpackage
