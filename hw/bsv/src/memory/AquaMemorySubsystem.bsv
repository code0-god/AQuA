package AquaMemorySubsystem;

import Assert::*;
import AccumulatorMem::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import Hp1MetaMem::*;
import LoadController::*;
import LoadStager::*;
import Scratchpad::*;
import StoreController::*;
import Vector::*;

interface AquaMemorySubsystemIfc#(
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
    numeric type rowShiftWidth,
    numeric type accumulatorBanks,
    numeric type accumulatorRows,
    numeric type accumulatorWidth
);
    method Bool loadReady;
    method Action scheduleLoad(ProviderLoadWork#(arrayDim) work);

    interface ReadPortIfc#(
        ActivationMemoryResponse#(arrayDim, activationWidth)
    ) activationPort;
    interface ReadPortIfc#(
        WeightMemoryResponse#(arrayDim, weightWidth)
    ) weightPort;
    interface ReadPortIfc#(
        BlockShiftMemoryResponse#(arrayDim, blockShiftWidth)
    ) blockShiftPort;
    interface ReadPortIfc#(
        RowScaleMemoryResponse#(arrayDim, rowShiftWidth)
    ) rowShiftPort;

    method Bool loadCompletionValid;
    method LoadCompletion loadCompletion;
    method Action consumeLoadCompletion;

    method Bool storeReady;
    method Action scheduleStore(StoreWork#(arrayDim) work);
    interface WritePortIfc#(accumulatorWidth) outputPort;
    method Bool storeCompletionValid;
    method StoreCompletion storeCompletion;
    method Action consumeStoreCompletion;

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
    interface AccumulatorMemIfc#(
        accumulatorBanks,
        accumulatorRows,
        accumulatorWidth
    ) accumulator;
endinterface

module mkAquaMemorySubsystem(
    AquaMemorySubsystemIfc#(
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
        rowShiftWidth,
        accumulatorBanks,
        accumulatorRows,
        accumulatorWidth
    )
) provisos (
    Add#(activationLanePadding, TLog#(arrayDim), 32),
    Add#(weightLanePadding, TLog#(arrayDim), 32),
    Add#(accBankPadding, TLog#(TAdd#(accumulatorBanks, 1)), 8),
    Add#(accRowPadding, TLog#(TAdd#(accumulatorRows, 1)), 16),
    Add#(activationBankPadding, TLog#(activationBanks), 32),
    Add#(activationRowPadding, TLog#(TAdd#(activationRows, 1)), 32),
    Add#(weightBankPadding, TLog#(weightBanks), 32),
    Add#(weightRowPadding, TLog#(TAdd#(weightRows, 1)), 32),
    Add#(blockMetaPadding, TLog#(TAdd#(blockMetaEntries, 1)), 32),
    Add#(rowMetaPadding, TLog#(TAdd#(rowMetaEntries, 1)), 32)
);
    staticAssert(
        valueOf(accumulatorBanks) == valueOf(arrayDim),
        "accumulator bank count must equal array dimension"
    );

    LoadControllerIfc#(
        arrayDim,
        activationBanks,
        activationRows,
        weightBanks,
        weightRows,
        blockMetaEntries,
        rowMetaEntries
    ) load <- mkLoadController;
    LoadStagerIfc#(
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
    ) staging <- mkLoadStager(load);
    AccumulatorMemIfc#(
        accumulatorBanks,
        accumulatorRows,
        accumulatorWidth
    ) accumulators <- mkAccumulatorMem;
    StoreControllerIfc#(
        arrayDim,
        accumulatorBanks,
        accumulatorRows,
        accumulatorWidth
    ) store <- mkStoreController(accumulators);

    method Bool loadReady = load.scheduleReady;
    method Action scheduleLoad(ProviderLoadWork#(arrayDim) work);
        load.schedule(work);
    endmethod

    interface ReadPortIfc activationPort;
        interface requests = load.activationPort.requests;
        interface responses = staging.activationResponses;
    endinterface

    interface ReadPortIfc weightPort;
        interface requests = load.weightPort.requests;
        interface responses = staging.weightResponses;
    endinterface

    interface ReadPortIfc blockShiftPort;
        interface requests = load.blockShiftPort.requests;
        interface responses = staging.blockShiftResponses;
    endinterface

    interface ReadPortIfc rowShiftPort;
        interface requests = load.rowShiftPort.requests;
        interface responses = staging.rowShiftResponses;
    endinterface

    method Bool loadCompletionValid = load.completionValid;
    method LoadCompletion loadCompletion if (load.completionValid);
        return load.completion;
    endmethod
    method Action consumeLoadCompletion if (load.completionValid);
        load.consumeCompletion;
    endmethod

    method Bool storeReady = store.startReady;
    method Action scheduleStore(StoreWork#(arrayDim) work);
        store.start(work);
    endmethod
    interface outputPort = store.outputPort;
    method Bool storeCompletionValid = store.completionValid;
    method StoreCompletion storeCompletion if (store.completionValid);
        return store.completion;
    endmethod
    method Action consumeStoreCompletion if (store.completionValid);
        store.consumeCompletion;
    endmethod

    interface activationBanks = staging.activationBanks;
    interface weightBanks = staging.weightBanks;
    interface hp1Meta = staging.hp1Meta;
    interface accumulator = accumulators;
endmodule

endpackage
