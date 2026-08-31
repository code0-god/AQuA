package MetadataResponseStager;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryTypes::*;
import LoadController::*;
import AquaTypes::*;
import Hp1MetaMem::*;

function UInt#(32) metadataLocalBank(AquaMemoryTag tag);
    return zeroExtend(unpack(tag.localDestination.bank));
endfunction

function UInt#(32) metadataLocalRow(AquaMemoryTag tag);
    return zeroExtend(unpack(tag.localDestination.row));
endfunction

function Bool validMetadataResponse(
    AquaMemoryTag tag,
    AquaMemoryKind expectedKind,
    Integer entryCount
);
    return
        tag.kind == expectedKind
        && tag.localDestination.region == LocalHp1Meta
        && metadataLocalBank(tag) == 0
        && metadataLocalRow(tag) < fromInteger(entryCount);
endfunction

interface MetadataResponseStagerIfc#(
    numeric type metaEntries,
    numeric type shiftWidth
);
    method Bool blockShiftResponseReady(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
    method Action putBlockShiftResponse(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
    method Bool queuedBlockShiftResponseReady(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
    method Action putQueuedBlockShiftResponse(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
    method Bool rowScaleResponseReady(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
    method Action putRowScaleResponse(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
    method Bool queuedRowScaleResponseReady(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
    method Action putQueuedRowScaleResponse(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
    interface Hp1MetaMemIfc#(metaEntries, shiftWidth) hp1Meta;
endinterface

module mkMetadataResponseStager#(
    LoadControllerIfc#(arrayDim, bankCount, metaEntries) load
)(MetadataResponseStagerIfc#(metaEntries, shiftWidth))
    provisos (
        Add#(metaPadding, TLog#(TAdd#(metaEntries, 1)), 32)
    );
    Hp1MetaMemIfc#(metaEntries, shiftWidth) metadata <- mkHp1MetaMem;

    method Bool blockShiftResponseReady(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
        return load.blockShiftResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1BlockShift,
                valueOf(metaEntries)
            );
    endmethod
    method Action putBlockShiftResponse(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
        UInt#(32) row = metadataLocalRow(response.tag);
        Hp1MetaAddr#(metaEntries) address = truncate(pack(row));
        Bool valid = load.blockShiftResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1BlockShift,
                valueOf(metaEntries)
            );
        dynamicAssert(valid, "block shift response is not outstanding");
        if (valid) begin
            metadata.writeBlockScale(address, response.payload);
            load.completeBlockShift(response.tag);
        end
    endmethod
    method Bool queuedBlockShiftResponseReady(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
        return load.queuedBlockShiftResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1BlockShift,
                valueOf(metaEntries)
            );
    endmethod
    method Action putQueuedBlockShiftResponse(
        AquaMemoryReadResponse#(Hp1BlockScale#(shiftWidth)) response
    );
        UInt#(32) row = metadataLocalRow(response.tag);
        Hp1MetaAddr#(metaEntries) address = truncate(pack(row));
        Bool valid = load.queuedBlockShiftResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1BlockShift,
                valueOf(metaEntries)
            );
        dynamicAssert(valid, "queued block shift response mismatch");
        if (valid) begin
            metadata.writeBlockScale(address, response.payload);
            load.completeQueuedBlockShift(response.tag);
        end
    endmethod

    method Bool rowScaleResponseReady(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
        return load.rowScaleResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1RowScale,
                valueOf(metaEntries)
            );
    endmethod
    method Action putRowScaleResponse(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
        UInt#(32) row = metadataLocalRow(response.tag);
        Hp1MetaAddr#(metaEntries) address = truncate(pack(row));
        Bool valid = load.rowScaleResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1RowScale,
                valueOf(metaEntries)
            );
        dynamicAssert(valid, "row scale response is not outstanding");
        if (valid) begin
            metadata.writeRowShift(address, response.payload);
            load.completeRowScale(response.tag);
        end
    endmethod
    method Bool queuedRowScaleResponseReady(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
        return load.queuedRowScaleResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1RowScale,
                valueOf(metaEntries)
            );
    endmethod
    method Action putQueuedRowScaleResponse(
        AquaMemoryReadResponse#(UInt#(shiftWidth)) response
    );
        UInt#(32) row = metadataLocalRow(response.tag);
        Hp1MetaAddr#(metaEntries) address = truncate(pack(row));
        Bool valid = load.queuedRowScaleResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1RowScale,
                valueOf(metaEntries)
            );
        dynamicAssert(valid, "queued row scale response mismatch");
        if (valid) begin
            metadata.writeRowShift(address, response.payload);
            load.completeQueuedRowScale(response.tag);
        end
    endmethod
    interface hp1Meta = metadata;
endmodule

endpackage
