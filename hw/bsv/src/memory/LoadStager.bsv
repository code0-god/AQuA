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
    numeric type metaEntries,
    numeric type activationWidth,
    numeric type weightWidth,
    numeric type shiftWidth
);
    interface ReadResponseSinkIfc#(
        ActivationMemoryResponse#(arrayDim, activationWidth)
    ) activationResponses;
    interface ReadResponseSinkIfc#(
        WeightMemoryResponse#(arrayDim, weightWidth)
    ) weightResponses;
    interface ReadResponseSinkIfc#(
        BlockShiftMemoryResponse#(arrayDim, shiftWidth)
    ) blockShiftResponses;
    interface ReadResponseSinkIfc#(
        RowScaleMemoryResponse#(arrayDim, shiftWidth)
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
    interface Hp1MetaMemIfc#(metaEntries, arrayDim, shiftWidth) hp1Meta;
endinterface

module mkLoadStager#(
    LoadControllerIfc#(
        arrayDim,
        activationBanks,
        weightBanks,
        metaEntries
    ) load
)(LoadStagerIfc#(
    arrayDim,
    activationBanks,
    activationRows,
    weightBanks,
    weightRows,
    metaEntries,
    activationWidth,
    weightWidth,
    shiftWidth
)) provisos (
    Add#(activationBankPadding, TLog#(activationBanks), 32),
    Add#(activationRowPadding, TLog#(TAdd#(activationRows, 1)), 32),
    Add#(weightBankPadding, TLog#(weightBanks), 32),
    Add#(weightRowPadding, TLog#(TAdd#(weightRows, 1)), 32),
    Add#(metaPadding, TLog#(TAdd#(metaEntries, 1)), 32)
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
    Hp1MetaMemIfc#(metaEntries, arrayDim, shiftWidth) metadata
        <- mkHp1MetaMem;

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
                );
        endmethod

        method Action put(
            ActivationMemoryResponse#(arrayDim, activationWidth) response
        );
            UInt#(32) bank = localBank(response.tag);
            UInt#(32) row = localRow(response.tag);
            UInt#(TLog#(activationBanks)) bankIndex = truncate(bank);
            ScratchpadRowAddr#(activationRows) rowAddress = truncate(pack(row));
            Bool valid = load.activationPort.responses.ready(response.tag)
                && validLocalResponse(
                    response.tag,
                    LocalActivation,
                    valueOf(activationBanks),
                    valueOf(activationRows)
                );
            dynamicAssert(valid, "activation response is not outstanding");
            if (valid) begin
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
                );
        endmethod

        method Action put(
            WeightMemoryResponse#(arrayDim, weightWidth) response
        );
            UInt#(32) bank = localBank(response.tag);
            UInt#(32) row = localRow(response.tag);
            UInt#(TLog#(weightBanks)) bankIndex = truncate(bank);
            ScratchpadRowAddr#(weightRows) rowAddress = truncate(pack(row));
            Bool valid = load.weightPort.responses.ready(response.tag)
                && validLocalResponse(
                    response.tag,
                    LocalWeight,
                    valueOf(weightBanks),
                    valueOf(weightRows)
                );
            dynamicAssert(valid, "weight response is not outstanding");
            if (valid) begin
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
            BlockShiftMemoryResponse#(arrayDim, shiftWidth) response
        );
            return load.blockShiftPort.responses.ready(response.tag)
                && validMetadataResponse(response.tag, valueOf(metaEntries))
                && load.metadataResponseMaskValid(response.payload.mask);
        endmethod

        method Action put(
            BlockShiftMemoryResponse#(arrayDim, shiftWidth) response
        );
            UInt#(32) row = localRow(response.tag);
            Hp1MetaAddr#(metaEntries) address = truncate(pack(row));
            Bool maskValid =
                load.metadataResponseMaskValid(response.payload.mask);
            Bool valid = load.blockShiftPort.responses.ready(response.tag)
                && validMetadataResponse(response.tag, valueOf(metaEntries));
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
            RowScaleMemoryResponse#(arrayDim, shiftWidth) response
        );
            return load.rowShiftPort.responses.ready(response.tag)
                && validMetadataResponse(response.tag, valueOf(metaEntries))
                && load.metadataResponseMaskValid(response.payload.mask);
        endmethod

        method Action put(
            RowScaleMemoryResponse#(arrayDim, shiftWidth) response
        );
            UInt#(32) row = localRow(response.tag);
            Hp1MetaAddr#(metaEntries) address = truncate(pack(row));
            Bool maskValid =
                load.metadataResponseMaskValid(response.payload.mask);
            Bool valid = load.rowShiftPort.responses.ready(response.tag)
                && validMetadataResponse(response.tag, valueOf(metaEntries));
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
