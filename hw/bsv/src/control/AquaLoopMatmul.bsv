package AquaLoopMatmul;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryProtocol::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import MatmulScheduler::*;
import WorkScheduler::*;

typedef enum {
    LoopIdle,
    LoopWaitArrayWork,
    LoopWaitFragment,
    LoopOfferLoad,
    LoopWaitLoad,
    LoopOfferExecute,
    LoopWaitExecute,
    LoopAdvanceFragment,
    LoopOfferStore,
    LoopWaitStore,
    LoopRetireWork
} LoopPhase deriving (Bits, Eq, FShow);

interface AquaLoopMatmulIfc#(numeric type arrayDim);
    method Bool startReady;
    method Action start(AquaMatmulDescriptor descriptor);

    method Bool publishReady;
    method Action publishStripe(ActivationStripe stripe);

    method Bool loadWorkValid;
    method ProviderLoadWork#(arrayDim) loadWork;
    method Action consumeLoadWork;

    method Bool loadCompletionReady(LoadCompletion completion);
    method Action putLoadCompletion(LoadCompletion completion);

    method Bool executeWorkValid;
    method ExecuteWork#(arrayDim) executeWork;
    method Action consumeExecuteWork;

    method Bool executeCompletionReady(ExecuteCompletion completion);
    method Action putExecuteCompletion(ExecuteCompletion completion);

    method Bool storeWorkValid;
    method StoreWork#(arrayDim) storeWork;
    method Action consumeStoreWork;

    method Bool storeCompletionReady(StoreCompletion completion);
    method Action putStoreCompletion(StoreCompletion completion);

    method Bool stripeCompletionValid;
    method StripeCompletion stripeCompletion;
    method Action consumeStripeCompletion;

    method UInt#(8) debugPhase;
endinterface

function AquaLocalAddr activationFragmentBase;
    return AquaLocalAddr {
        region: LocalActivation,
        bank: 0,
        row: 0
    };
endfunction

function AquaLocalAddr weightFragmentBase;
    return AquaLocalAddr {
        region: LocalWeight,
        bank: 0,
        row: 0
    };
endfunction

function AquaLocalAddr blockShiftBase;
    return AquaLocalAddr {
        region: LocalHp1Meta,
        bank: 0,
        row: 0
    };
endfunction

function AquaLocalAddr rowShiftBase;
    return AquaLocalAddr {
        region: LocalHp1Meta,
        bank: 0,
        row: 0
    };
endfunction

function UInt#(64) accumulatorBaseRow(
    ArrayWork#(arrayDim) work,
    MatrixExtent arrayDimension
);
    MatrixExtent iRelative = work.iStart - work.stripeRowBegin;
    MatrixExtent jRelative = work.jStart - work.macroNStart;
    UInt#(64) dimension = zeroExtend(arrayDimension);
    UInt#(64) iGroup = zeroExtend(iRelative) / dimension;
    UInt#(64) jGroup = zeroExtend(jRelative) / dimension;
    UInt#(64) jGroupCount =
        zeroExtend(work.macroNCount - 1) / dimension + 1;
    return (
        iGroup * jGroupCount
        + jGroup
    ) * dimension;
endfunction

function Bool accumulatorBaseValid(
    ArrayWork#(arrayDim) work,
    MatrixExtent arrayDimension
);
    UInt#(64) baseRow = accumulatorBaseRow(work, arrayDimension);
    UInt#(64) rowEnd = baseRow + zeroExtend(work.iCount);
    return
        work.iStart >= work.stripeRowBegin
        && work.jStart >= work.macroNStart
        && work.macroNCount > 0
        && rowEnd <= fromInteger(2 ** 16);
endfunction

function AquaLocalAddr accumulatorBase(
    ArrayWork#(arrayDim) work,
    MatrixExtent arrayDimension
);
    UInt#(64) baseRow = accumulatorBaseRow(work, arrayDimension);
    return AquaLocalAddr {
        region: LocalAccumulator,
        bank: 0,
        row: truncate(pack(baseRow))
    };
endfunction

function ProviderLoadWork#(arrayDim) makeLoadWork(
    AquaMatmulDescriptor descriptor,
    ArrayWork#(arrayDim) work,
    KFragment fragment,
    ArrayWorkId arrayWorkId,
    KFragmentId fragmentId
);
    return ProviderLoadWork {
        jobId: work.jobId,
        stripeId: work.stripeId,
        arrayWorkId: arrayWorkId,
        fragmentId: fragmentId,
        activationTensor: descriptor.activationTensor,
        weightTensor: descriptor.weightTensor,
        iStart: work.iStart,
        iCount: work.iCount,
        jStart: work.jStart,
        jCount: work.jCount,
        fragmentKStart: fragment.fragmentKStart,
        fragmentKCount: fragment.fragmentKCount,
        fragmentBlockIndex: fragment.fragmentBlockIndex,
        activationBase: activationFragmentBase,
        weightBase: weightFragmentBase,
        blockShiftDestination: blockShiftBase,
        rowScaleDestination: rowShiftBase
    };
endfunction

function ExecuteWork#(arrayDim) makeExecuteWork(
    ArrayWork#(arrayDim) work,
    KFragment fragment,
    ArrayWorkId arrayWorkId,
    KFragmentId fragmentId,
    MatrixExtent arrayDimension
);
    return ExecuteWork {
        jobId: work.jobId,
        stripeId: work.stripeId,
        arrayWorkId: arrayWorkId,
        fragmentId: fragmentId,
        iStart: work.iStart,
        iCount: work.iCount,
        jStart: work.jStart,
        jCount: work.jCount,
        fragmentKStart: fragment.fragmentKStart,
        fragmentKCount: fragment.fragmentKCount,
        fragmentBlockIndex: fragment.fragmentBlockIndex,
        fragmentEndsBlock: fragment.fragmentEndsBlock,
        activationBase: activationFragmentBase,
        weightBase: weightFragmentBase,
        blockShiftAddress: blockShiftBase,
        rowShiftAddress: rowShiftBase,
        accumulatorBase: accumulatorBase(work, arrayDimension),
        accumulate: fragment.accumulate
    };
endfunction

function StoreWork#(arrayDim) makeStoreWork(
    AquaMatmulDescriptor descriptor,
    ArrayWork#(arrayDim) work,
    ArrayWorkId arrayWorkId,
    MatrixExtent arrayDimension
);
    return StoreWork {
        jobId: work.jobId,
        stripeId: work.stripeId,
        arrayWorkId: arrayWorkId,
        outputTensor: descriptor.outputTensor,
        iStart: work.iStart,
        iCount: work.iCount,
        jStart: work.jStart,
        jCount: work.jCount,
        accumulatorBase: accumulatorBase(work, arrayDimension)
    };
endfunction

module mkAquaLoopMatmul(AquaLoopMatmulIfc#(arrayDim));
    staticAssert(
        valueOf(arrayDim) == 16
        || valueOf(arrayDim) == 32
        || valueOf(arrayDim) == 64,
        "loop matmul DIM must be 16, 32, or 64"
    );

    MatmulSchedulerIfc#(arrayDim) matmul <- mkMatmulScheduler;
    WorkSchedulerIfc#(arrayDim) fragments <- mkWorkScheduler;

    Reg#(LoopPhase) phase <- mkReg(LoopIdle);
    Reg#(Maybe#(AquaMatmulDescriptor)) activeDescriptor
        <- mkReg(tagged Invalid);
    Reg#(Maybe#(ArrayWork#(arrayDim))) activeWork
        <- mkReg(tagged Invalid);
    Reg#(ArrayWorkId) arrayWorkId <- mkReg(0);
    Reg#(UInt#(33)) nextArrayWorkId <- mkReg(0);
    Reg#(KFragmentId) fragmentId <- mkReg(0);

    MatrixExtent arrayDimension = fromInteger(valueOf(arrayDim));

    rule beginArrayWork(
        phase == LoopWaitArrayWork
        && !matmul.completionValid
        && matmul.workValid
        && fragments.startReady
    );
        let work = matmul.currentWork;
        Bool idValid =
            nextArrayWorkId <= fromInteger(2 ** 32 - 1);
        Bool valid =
            idValid
            && accumulatorBaseValid(work, arrayDimension);
        dynamicAssert(idValid, "array work ID overflow");
        dynamicAssert(
            accumulatorBaseValid(work, arrayDimension),
            "accumulator local row exceeds address width"
        );
        if (valid) begin
            activeWork <= tagged Valid work;
            arrayWorkId <= truncate(nextArrayWorkId);
            fragmentId <= 0;
            fragments.start(work, work.kTileStart != 0);
            phase <= LoopOfferLoad;
        end
    endrule

    rule retireFragment(
        phase == LoopAdvanceFragment
        && fragments.fragmentValid
    );
        if (fragments.lookaheadValid) begin
            fragmentId <= fragmentId + 1;
            phase <= LoopOfferLoad;
        end
        else begin
            phase <= LoopWaitFragment;
        end
        fragments.consumeFragment;
    endrule

    rule finishFragments(
        phase == LoopWaitFragment
        && fragments.doneValid
    );
        let descriptor = fromMaybe(?, activeDescriptor);
        let work = fromMaybe(?, activeWork);
        UInt#(33) kEnd =
            zeroExtend(work.kTileStart)
            + zeroExtend(work.kTileCount);
        Bool valid = kEnd <= zeroExtend(descriptor.k);
        dynamicAssert(valid, "macro K work exceeds logical K");
        if (valid) begin
            fragments.consumeDone;
            phase <= kEnd == zeroExtend(descriptor.k)
                ? LoopOfferStore
                : LoopRetireWork;
        end
    endrule

    rule retireWork(phase == LoopRetireWork);
        matmul.completeWork;
        nextArrayWorkId <= nextArrayWorkId + 1;
        activeWork <= tagged Invalid;
        phase <= LoopWaitArrayWork;
    endrule

    rule finishJob(
        phase == LoopWaitArrayWork
        && isValid(activeDescriptor)
        && matmul.startReady
    );
        activeDescriptor <= tagged Invalid;
        phase <= LoopIdle;
    endrule

    method Bool startReady =
        phase == LoopIdle
        && matmul.startReady;

    method Action start(AquaMatmulDescriptor descriptor)
        if (phase == LoopIdle && matmul.startReady);
        Bool valid = validDescriptor(descriptor);
        dynamicAssert(valid, "invalid loop matmul descriptor");
        if (valid) begin
            matmul.start(descriptor);
            activeDescriptor <= tagged Valid descriptor;
            activeWork <= tagged Invalid;
            arrayWorkId <= 0;
            nextArrayWorkId <= 0;
            fragmentId <= 0;
            phase <= LoopWaitArrayWork;
        end
    endmethod

    method Bool publishReady =
        phase != LoopIdle
        && matmul.publishReady;

    method Action publishStripe(ActivationStripe stripe)
        if (phase != LoopIdle && matmul.publishReady);
        matmul.publishStripe(stripe);
    endmethod

    method Bool loadWorkValid =
        phase == LoopOfferLoad
        && isValid(activeDescriptor)
        && isValid(activeWork)
        && fragments.fragmentValid;

    method ProviderLoadWork#(arrayDim) loadWork
        if (
            phase == LoopOfferLoad
            && isValid(activeDescriptor)
            && isValid(activeWork)
            && fragments.fragmentValid
        );
        return makeLoadWork(
            fromMaybe(?, activeDescriptor),
            fromMaybe(?, activeWork),
            fragments.currentFragment,
            arrayWorkId,
            fragmentId
        );
    endmethod

    method Action consumeLoadWork
        if (
            phase == LoopOfferLoad
            && isValid(activeDescriptor)
            && isValid(activeWork)
            && fragments.fragmentValid
        );
        phase <= LoopWaitLoad;
    endmethod

    method Bool loadCompletionReady(LoadCompletion completion);
        Bool valid = False;
        if (phase == LoopWaitLoad && isValid(activeWork)) begin
            let work = fromMaybe(?, activeWork);
            valid =
                completion.jobId == work.jobId
                && completion.stripeId == work.stripeId
                && completion.arrayWorkId == arrayWorkId
                && completion.fragmentId == fragmentId;
        end
        return valid;
    endmethod

    method Action putLoadCompletion(LoadCompletion completion)
        if (phase == LoopWaitLoad);
        Bool valid = False;
        if (phase == LoopWaitLoad && isValid(activeWork)) begin
            let work = fromMaybe(?, activeWork);
            valid =
                completion.jobId == work.jobId
                && completion.stripeId == work.stripeId
                && completion.arrayWorkId == arrayWorkId
                && completion.fragmentId == fragmentId;
        end
        dynamicAssert(valid, "load completion mismatch");
        if (valid) phase <= LoopOfferExecute;
    endmethod

    method Bool executeWorkValid =
        phase == LoopOfferExecute
        && isValid(activeWork)
        && fragments.fragmentValid;

    method ExecuteWork#(arrayDim) executeWork
        if (
            phase == LoopOfferExecute
            && isValid(activeWork)
            && fragments.fragmentValid
        );
        return makeExecuteWork(
            fromMaybe(?, activeWork),
            fragments.currentFragment,
            arrayWorkId,
            fragmentId,
            arrayDimension
        );
    endmethod

    method Action consumeExecuteWork
        if (
            phase == LoopOfferExecute
            && isValid(activeWork)
            && fragments.fragmentValid
        );
        phase <= LoopWaitExecute;
    endmethod

    method Bool executeCompletionReady(ExecuteCompletion completion);
        Bool valid = False;
        if (phase == LoopWaitExecute && isValid(activeWork)) begin
            let work = fromMaybe(?, activeWork);
            valid =
                completion.jobId == work.jobId
                && completion.stripeId == work.stripeId
                && completion.arrayWorkId == arrayWorkId
                && completion.fragmentId == fragmentId;
        end
        return valid;
    endmethod

    method Action putExecuteCompletion(ExecuteCompletion completion)
        if (phase == LoopWaitExecute);
        Bool valid = False;
        if (phase == LoopWaitExecute && isValid(activeWork)) begin
            let work = fromMaybe(?, activeWork);
            valid =
                completion.jobId == work.jobId
                && completion.stripeId == work.stripeId
                && completion.arrayWorkId == arrayWorkId
                && completion.fragmentId == fragmentId;
        end
        dynamicAssert(valid, "execute completion mismatch");
        if (valid) begin
            phase <= LoopAdvanceFragment;
        end
    endmethod

    method Bool storeWorkValid =
        phase == LoopOfferStore
        && isValid(activeDescriptor)
        && isValid(activeWork);

    method StoreWork#(arrayDim) storeWork
        if (
            phase == LoopOfferStore
            && isValid(activeDescriptor)
            && isValid(activeWork)
        );
        return makeStoreWork(
            fromMaybe(?, activeDescriptor),
            fromMaybe(?, activeWork),
            arrayWorkId,
            arrayDimension
        );
    endmethod

    method Action consumeStoreWork
        if (
            phase == LoopOfferStore
            && isValid(activeDescriptor)
            && isValid(activeWork)
        );
        phase <= LoopWaitStore;
    endmethod

    method Bool storeCompletionReady(StoreCompletion completion);
        Bool valid = False;
        if (phase == LoopWaitStore && isValid(activeWork)) begin
            let work = fromMaybe(?, activeWork);
            valid =
                completion.jobId == work.jobId
                && completion.stripeId == work.stripeId
                && completion.arrayWorkId == arrayWorkId;
        end
        return valid;
    endmethod

    method Action putStoreCompletion(StoreCompletion completion)
        if (phase == LoopWaitStore);
        Bool valid = False;
        if (phase == LoopWaitStore && isValid(activeWork)) begin
            let work = fromMaybe(?, activeWork);
            valid =
                completion.jobId == work.jobId
                && completion.stripeId == work.stripeId
                && completion.arrayWorkId == arrayWorkId;
        end
        dynamicAssert(valid, "store completion mismatch");
        if (valid) phase <= LoopRetireWork;
    endmethod

    method Bool stripeCompletionValid = matmul.completionValid;

    method StripeCompletion stripeCompletion
        if (matmul.completionValid);
        return matmul.completion;
    endmethod

    method Action consumeStripeCompletion
        if (matmul.completionValid);
        matmul.consumeCompletion;
    endmethod

    method UInt#(8) debugPhase;
        return zeroExtend(unpack(pack(phase)));
    endmethod
endmodule

endpackage
