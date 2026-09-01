package LoadStager;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import Hp1MetaMem::*;
import LoadController::*;
import Scratchpad::*;
import Vector::*;

function UInt#(32) localBank(AquaMemoryTag tag);
    return zeroExtend(unpack(tag.localAddress.bank));
endfunction

function UInt#(32) localRow(AquaMemoryTag tag);
    return zeroExtend(unpack(tag.localAddress.row));
endfunction

function Bool validLocalResponse(
    AquaMemoryTag tag,
    AquaLocalRegion expectedRegion,
    Integer bankCount,
    Integer rowCount
);
    return
        tag.localAddress.region == expectedRegion
        && localBank(tag) < fromInteger(bankCount)
        && localRow(tag) < fromInteger(rowCount);
endfunction

function Bool validMetadataResponse(
    AquaMemoryTag tag,
    Integer entryCount
);
    return
        tag.localAddress.region == LocalHp1Meta
        && localBank(tag) == 0
        && localRow(tag) < fromInteger(entryCount);
endfunction

interface LoadStagerIfc#(
    numeric type arrayDim,
    numeric type activationBanks,
    numeric type activationRows,
    numeric type weightBanks,
    numeric type weightRows,
    numeric type blockMetaEntries,
    numeric type rowMetaEntries,
    numeric type activationWidth,
    numeric type weightWidth,
    numeric type blockShiftWidth,
    numeric type rowShiftWidth
);
    interface ReadResponseSinkIfc#(
        ActivationMemoryResponse#(arrayDim, activationWidth)
    ) activationResponses;
    interface ReadResponseSinkIfc#(
        WeightMemoryResponse#(arrayDim, weightWidth)
    ) weightResponses;
    interface ReadResponseSinkIfc#(
        BlockShiftMemoryResponse#(arrayDim, blockShiftWidth)
    ) blockShiftResponses;
    interface ReadResponseSinkIfc#(
        RowScaleMemoryResponse#(arrayDim, rowShiftWidth)
    ) rowShiftResponses;

    interface Vector#(
        activationBanks,
        ScratchpadBankIfc#(
            activationRows,
            arrayDim,
            Int#(activationWidth)
        )
    ) activationBanks;
    interface Vector#(
        weightBanks,
        ScratchpadBankIfc#(
            weightRows,
            arrayDim,
            Bit#(weightWidth)
        )
    ) weightBanks;
    interface Hp1MetaMemIfc#(
        blockMetaEntries,
        rowMetaEntries,
        arrayDim,
        blockShiftWidth,
        rowShiftWidth
    ) hp1Meta;
endinterface

module mkLoadStager#(
    LoadControllerIfc#(
        arrayDim,
        activationBanks,
        activationRows,
        weightBanks,
        weightRows,
        blockMetaEntries,
        rowMetaEntries
    ) load
)(LoadStagerIfc#(
    arrayDim,
    activationBanks,
    activationRows,
    weightBanks,
    weightRows,
    blockMetaEntries,
    rowMetaEntries,
    activationWidth,
    weightWidth,
    blockShiftWidth,
    rowShiftWidth
)) provisos (
    Add#(activationBankPadding, TLog#(activationBanks), 32),
    Add#(activationRowPadding, TLog#(TAdd#(activationRows, 1)), 32),
    Add#(weightBankPadding, TLog#(weightBanks), 32),
    Add#(weightRowPadding, TLog#(TAdd#(weightRows, 1)), 32),
    Add#(blockMetaPadding, TLog#(TAdd#(blockMetaEntries, 1)), 32),
    Add#(rowMetaPadding, TLog#(TAdd#(rowMetaEntries, 1)), 32)
);
    BankedScratchpadIfc#(
        activationBanks,
        activationRows,
        arrayDim,
        Int#(activationWidth)
    ) activations <- mkBankedScratchpad;
    BankedScratchpadIfc#(
        weightBanks,
        weightRows,
        arrayDim,
        Bit#(weightWidth)
    ) weights <- mkBankedScratchpad;
    Hp1MetaMemIfc#(
        blockMetaEntries,
        rowMetaEntries,
        arrayDim,
        blockShiftWidth,
        rowShiftWidth
    ) metadata <- mkHp1MetaMem;

    interface ReadResponseSinkIfc activationResponses;
        method Bool ready(
            ActivationMemoryResponse#(arrayDim, activationWidth) response
        );
            return load.activationPort.responses.ready(response.tag)
                && validLocalResponse(
                    response.tag,
                    LocalActivation,
                    valueOf(activationBanks),
                    valueOf(activationRows)
                )
                && load.dataResponseMaskValid(response.payload.mask);
        endmethod

        method Action put(
            ActivationMemoryResponse#(arrayDim, activationWidth) response
        );
            UInt#(32) bank = localBank(response.tag);
            UInt#(32) row = localRow(response.tag);
            UInt#(TLog#(activationBanks)) bankIndex = truncate(bank);
            ScratchpadRowAddr#(activationRows) rowAddress = truncate(pack(row));
            Bool maskValid =
                load.dataResponseMaskValid(response.payload.mask);
            Bool valid = load.activationPort.responses.ready(response.tag)
                && validLocalResponse(
                    response.tag,
                    LocalActivation,
                    valueOf(activationBanks),
                    valueOf(activationRows)
                );
            dynamicAssert(
                maskValid,
                "activation response mask does not match requested K count"
            );
            dynamicAssert(valid, "activation response is not outstanding");
            if (valid && maskValid) begin
                activations.banks[bankIndex].write(
                    rowAddress,
                    response.payload.mask,
                    response.payload.data
                );
                load.activationPort.responses.put(response.tag);
            end
        endmethod
    endinterface

    interface ReadResponseSinkIfc weightResponses;
        method Bool ready(
            WeightMemoryResponse#(arrayDim, weightWidth) response
        );
            return load.weightPort.responses.ready(response.tag)
                && validLocalResponse(
                    response.tag,
                    LocalWeight,
                    valueOf(weightBanks),
                    valueOf(weightRows)
                )
                && load.dataResponseMaskValid(response.payload.mask);
        endmethod

        method Action put(
            WeightMemoryResponse#(arrayDim, weightWidth) response
        );
            UInt#(32) bank = localBank(response.tag);
            UInt#(32) row = localRow(response.tag);
            UInt#(TLog#(weightBanks)) bankIndex = truncate(bank);
            ScratchpadRowAddr#(weightRows) rowAddress = truncate(pack(row));
            Bool maskValid =
                load.dataResponseMaskValid(response.payload.mask);
            Bool valid = load.weightPort.responses.ready(response.tag)
                && validLocalResponse(
                    response.tag,
                    LocalWeight,
                    valueOf(weightBanks),
                    valueOf(weightRows)
                );
            dynamicAssert(
                maskValid,
                "weight response mask does not match requested K count"
            );
            dynamicAssert(valid, "weight response is not outstanding");
            if (valid && maskValid) begin
                weights.banks[bankIndex].write(
                    rowAddress,
                    response.payload.mask,
                    response.payload.data
                );
                load.weightPort.responses.put(response.tag);
            end
        endmethod
    endinterface

    interface ReadResponseSinkIfc blockShiftResponses;
        method Bool ready(
            BlockShiftMemoryResponse#(arrayDim, blockShiftWidth) response
        );
            return load.blockShiftPort.responses.ready(response.tag)
                && validMetadataResponse(
                    response.tag,
                    valueOf(blockMetaEntries)
                )
                && load.metadataResponseMaskValid(response.payload.mask);
        endmethod

        method Action put(
            BlockShiftMemoryResponse#(arrayDim, blockShiftWidth) response
        );
            UInt#(32) row = localRow(response.tag);
            Hp1BlockMetaAddr#(blockMetaEntries) address =
                truncate(pack(row));
            Bool maskValid =
                load.metadataResponseMaskValid(response.payload.mask);
            Bool valid = load.blockShiftPort.responses.ready(response.tag)
                && validMetadataResponse(
                    response.tag,
                    valueOf(blockMetaEntries)
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
                load.blockShiftPort.responses.put(response.tag);
            end
        endmethod
    endinterface

    interface ReadResponseSinkIfc rowShiftResponses;
        method Bool ready(
            RowScaleMemoryResponse#(arrayDim, rowShiftWidth) response
        );
            return load.rowShiftPort.responses.ready(response.tag)
                && validMetadataResponse(
                    response.tag,
                    valueOf(rowMetaEntries)
                )
                && load.metadataResponseMaskValid(response.payload.mask);
        endmethod

        method Action put(
            RowScaleMemoryResponse#(arrayDim, rowShiftWidth) response
        );
            UInt#(32) row = localRow(response.tag);
            Hp1RowMetaAddr#(rowMetaEntries) address = truncate(pack(row));
            Bool maskValid =
                load.metadataResponseMaskValid(response.payload.mask);
            Bool valid = load.rowShiftPort.responses.ready(response.tag)
                && validMetadataResponse(
                    response.tag,
                    valueOf(rowMetaEntries)
                );
            dynamicAssert(
                maskValid,
                "metadata response mask does not match requested J count"
            );
            dynamicAssert(valid, "row shift response is not outstanding");
            if (valid && maskValid) begin
                metadata.writeRowShifts(
                    address,
                    response.payload.mask,
                    response.payload.data
                );
                load.rowShiftPort.responses.put(response.tag);
            end
        endmethod
    endinterface

    interface activationBanks = activations.banks;
    interface weightBanks = weights.banks;
    interface hp1Meta = metadata;
endmodule

endpackage
