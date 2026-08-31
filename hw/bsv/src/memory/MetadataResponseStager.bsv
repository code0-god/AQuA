package MetadataResponseStager;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryTypes::*;
import LoadController::*;
import AquaTypes::*;
import Hp1MetaMem::*;

function UInt#(32) metadataLocalBank(AquaMemoryTag tag);
    return zeroExtend(unpack(tag.localAddress.bank));
endfunction

function UInt#(32) metadataLocalRow(AquaMemoryTag tag);
    return zeroExtend(unpack(tag.localAddress.row));
endfunction

function Bool validMetadataResponse(
    AquaMemoryTag tag,
    AquaMemoryKind expectedKind,
    Integer entryCount
);
    return
        tag.kind == expectedKind
        && tag.localAddress.region == LocalHp1Meta
        && metadataLocalBank(tag) == 0
        && metadataLocalRow(tag) < fromInteger(entryCount);
endfunction

interface MetadataResponseStagerIfc#(
    numeric type arrayDim,
    numeric type metaEntries,
    numeric type shiftWidth
);
    method Bool blockShiftResponseReady(
        BlockShiftMemoryResponse#(arrayDim, shiftWidth) response
    );
    method Action putBlockShiftResponse(
        BlockShiftMemoryResponse#(arrayDim, shiftWidth) response
    );
    method Bool queuedBlockShiftResponseReady(
        BlockShiftMemoryResponse#(arrayDim, shiftWidth) response
    );
    method Action putQueuedBlockShiftResponse(
        BlockShiftMemoryResponse#(arrayDim, shiftWidth) response
    );
    method Bool rowScaleResponseReady(
        RowScaleMemoryResponse#(arrayDim, shiftWidth) response
    );
    method Action putRowScaleResponse(
        RowScaleMemoryResponse#(arrayDim, shiftWidth) response
    );
    method Bool queuedRowScaleResponseReady(
        RowScaleMemoryResponse#(arrayDim, shiftWidth) response
    );
    method Action putQueuedRowScaleResponse(
        RowScaleMemoryResponse#(arrayDim, shiftWidth) response
    );
    interface Hp1MetaMemIfc#(metaEntries, arrayDim, shiftWidth) hp1Meta;
endinterface

module mkMetadataResponseStager#(
    LoadControllerIfc#(arrayDim, bankCount, metaEntries) load
)(MetadataResponseStagerIfc#(arrayDim, metaEntries, shiftWidth))
    provisos (
        Add#(metaPadding, TLog#(TAdd#(metaEntries, 1)), 32)
    );
    Hp1MetaMemIfc#(metaEntries, arrayDim, shiftWidth) metadata
        <- mkHp1MetaMem;

    method Bool blockShiftResponseReady(
        BlockShiftMemoryResponse#(arrayDim, shiftWidth) response
    );
        return load.blockShiftResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1BlockShift,
                valueOf(metaEntries)
            )
            && load.metadataResponseMaskValid(response.payload.mask);
    endmethod

    method Action putBlockShiftResponse(
        BlockShiftMemoryResponse#(arrayDim, shiftWidth) response
    );
        UInt#(32) row = metadataLocalRow(response.tag);
        Hp1MetaAddr#(metaEntries) address = truncate(pack(row));
        Bool maskValid = load.metadataResponseMaskValid(response.payload.mask);
        Bool valid = load.blockShiftResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1BlockShift,
                valueOf(metaEntries)
            );
        dynamicAssert(
            maskValid,
            "metadata response mask does not match requested J count"
        );
        dynamicAssert(valid, "block shift response is not outstanding");
        if (valid && maskValid) begin
            metadata.writeBlockScales(
                address,
                response.payload.mask,
                response.payload.data
            );
            load.completeBlockShift(response.tag);
        end
    endmethod

    method Bool queuedBlockShiftResponseReady(
        BlockShiftMemoryResponse#(arrayDim, shiftWidth) response
    );
        return load.queuedBlockShiftResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1BlockShift,
                valueOf(metaEntries)
            )
            && load.metadataResponseMaskValid(response.payload.mask);
    endmethod

    method Action putQueuedBlockShiftResponse(
        BlockShiftMemoryResponse#(arrayDim, shiftWidth) response
    );
        UInt#(32) row = metadataLocalRow(response.tag);
        Hp1MetaAddr#(metaEntries) address = truncate(pack(row));
        Bool maskValid = load.metadataResponseMaskValid(response.payload.mask);
        Bool valid = load.queuedBlockShiftResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1BlockShift,
                valueOf(metaEntries)
            );
        dynamicAssert(
            maskValid,
            "metadata response mask does not match requested J count"
        );
        dynamicAssert(valid, "queued block shift response mismatch");
        if (valid && maskValid) begin
            metadata.writeBlockScales(
                address,
                response.payload.mask,
                response.payload.data
            );
            load.completeQueuedBlockShift(response.tag);
        end
    endmethod

    method Bool rowScaleResponseReady(
        RowScaleMemoryResponse#(arrayDim, shiftWidth) response
    );
        return load.rowScaleResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1RowScale,
                valueOf(metaEntries)
            )
            && load.metadataResponseMaskValid(response.payload.mask);
    endmethod

    method Action putRowScaleResponse(
        RowScaleMemoryResponse#(arrayDim, shiftWidth) response
    );
        UInt#(32) row = metadataLocalRow(response.tag);
        Hp1MetaAddr#(metaEntries) address = truncate(pack(row));
        Bool maskValid = load.metadataResponseMaskValid(response.payload.mask);
        Bool valid = load.rowScaleResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1RowScale,
                valueOf(metaEntries)
            );
        dynamicAssert(
            maskValid,
            "metadata response mask does not match requested J count"
        );
        dynamicAssert(valid, "row scale response is not outstanding");
        if (valid && maskValid) begin
            metadata.writeRowShifts(
                address,
                response.payload.mask,
                response.payload.data
            );
            load.completeRowScale(response.tag);
        end
    endmethod

    method Bool queuedRowScaleResponseReady(
        RowScaleMemoryResponse#(arrayDim, shiftWidth) response
    );
        return load.queuedRowScaleResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1RowScale,
                valueOf(metaEntries)
            )
            && load.metadataResponseMaskValid(response.payload.mask);
    endmethod

    method Action putQueuedRowScaleResponse(
        RowScaleMemoryResponse#(arrayDim, shiftWidth) response
    );
        UInt#(32) row = metadataLocalRow(response.tag);
        Hp1MetaAddr#(metaEntries) address = truncate(pack(row));
        Bool maskValid = load.metadataResponseMaskValid(response.payload.mask);
        Bool valid = load.queuedRowScaleResponseReady(response.tag)
            && validMetadataResponse(
                response.tag,
                MemoryHp1RowScale,
                valueOf(metaEntries)
            );
        dynamicAssert(
            maskValid,
            "metadata response mask does not match requested J count"
        );
        dynamicAssert(valid, "queued row scale response mismatch");
        if (valid && maskValid) begin
            metadata.writeRowShifts(
                address,
                response.payload.mask,
                response.payload.data
            );
            load.completeQueuedRowScale(response.tag);
        end
    endmethod

    interface hp1Meta = metadata;
endmodule

endpackage
