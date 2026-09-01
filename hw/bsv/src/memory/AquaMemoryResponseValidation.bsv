package AquaMemoryResponseValidation;

import AquaLocalAddr::*;
import AquaMemoryTypes::*;

function UInt#(32) localBank(AquaMemoryTag tag);
    return zeroExtend(unpack(tag.localDestination.bank));
endfunction

function UInt#(32) localRow(AquaMemoryTag tag);
    return zeroExtend(unpack(tag.localDestination.row));
endfunction

function Bool validScratchpadResponse(
    AquaMemoryTag tag,
    AquaMemoryKind expectedKind,
    AquaLocalRegion expectedRegion,
    Integer bankCount,
    Integer rowCount
);
    return
        tag.kind == expectedKind
        && tag.localDestination.region == expectedRegion
        && localBank(tag) < fromInteger(bankCount)
        && localRow(tag) < fromInteger(rowCount);
endfunction

function Bool validMetadataResponse(
    AquaMemoryTag tag,
    AquaMemoryKind expectedKind,
    Integer entryCount
);
    return
        tag.kind == expectedKind
        && tag.localDestination.region == LocalHp1Meta
        && localBank(tag) == 0
        && localRow(tag) < fromInteger(entryCount);
endfunction

endpackage
