package MatmulScheduler;

import Assert::*;
import FIFOF::*;
import AquaLocalAddr::*;
import AquaMath::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import MatmulScheduleMath::*;

interface MatmulSchedulerIfc#(numeric type arrayDim);
    method Bool startReady;
    method Action start(AquaMatmulDescriptor descriptor);

    method Bool publishReady;
    method Action publishStripe(ActivationStripe stripe);

    method Bool workValid;
    method ArrayWork#(arrayDim) currentWork;
    // The consumer calls completeWork only after the exposed array work
    // retires. The scheduler never advances on issue alone.
    method Action completeWork;

    method Bool lookaheadValid;
    method ActivationStripe lookaheadStripe;

    method Bool completionValid;
    method StripeCompletion completion;
    method Action consumeCompletion;
endinterface

module mkMatmulScheduler(MatmulSchedulerIfc#(arrayDim))
    provisos (
        Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32)
    );

    FIFOF#(StripeCompletion) completions <- mkSizedFIFOF(2);
    Reg#(Maybe#(AquaMatmulDescriptor)) activeDescriptor
        <- mkReg(tagged Invalid);
    Reg#(Maybe#(ActivationStripe)) activeStripe
        <- mkReg(tagged Invalid);
    Reg#(Maybe#(ActivationStripe)) stripeLookahead
        <- mkReg(tagged Invalid);
    Reg#(MatrixExtent) macroNStart <- mkReg(0);
    Reg#(MatrixExtent) iStart <- mkReg(0);
    Reg#(MatrixExtent) jStart <- mkReg(0);
    Reg#(MatrixExtent) publishedUntil <- mkReg(0);
    Reg#(StripeId) nextStripeId <- mkReg(0);

    MatrixExtent arrayDimension = fromInteger(valueOf(arrayDim));

    method Bool startReady =
        !isValid(activeDescriptor)
        && !isValid(activeStripe)
        && !isValid(stripeLookahead)
        && !completions.notEmpty;

    method Action start(AquaMatmulDescriptor descriptor)
        if (
            !isValid(activeDescriptor)
            && !isValid(activeStripe)
            && !isValid(stripeLookahead)
            && !completions.notEmpty
        );
        dynamicAssert(descriptor.m > 0, "matmul M must be positive");
        dynamicAssert(descriptor.n > 0, "matmul N must be positive");
        dynamicAssert(descriptor.k > 0, "matmul K must be positive");
        dynamicAssert(descriptor.stripeRows > 0, "stripe rows must be positive");
        dynamicAssert(
            descriptor.macroNTileColumns > 0,
            "macro N tile must be positive"
        );
        dynamicAssert(
            descriptor.macroKTileElements > 0,
            "macro K tile must be positive"
        );

        activeDescriptor <= tagged Valid descriptor;
        publishedUntil <= 0;
        nextStripeId <= 0;
        macroNStart <= 0;
        iStart <= 0;
        jStart <= 0;

        if (descriptor.mode == FullMatrix) begin
            ActivationStripe first = makeFullStripe(descriptor, 0, 0);
            MatrixExtent nextBegin = first.rowBegin + first.rowCount;
            Maybe#(ActivationStripe) next = tagged Invalid;
            if (nextBegin < descriptor.m) begin
                next = tagged Valid makeFullStripe(
                    descriptor,
                    1,
                    nextBegin
                );
            end
            activeStripe <= tagged Valid first;
            stripeLookahead <= next;
        end
        else begin
            activeStripe <= tagged Invalid;
            stripeLookahead <= tagged Invalid;
        end
    endmethod

    method Bool publishReady =
        isValid(activeDescriptor)
        && fromMaybe(?, activeDescriptor).mode == AsyncStripes
        && publishedUntil < fromMaybe(?, activeDescriptor).m
        && (
            !isValid(activeStripe)
            || !isValid(stripeLookahead)
        );

    method Action publishStripe(ActivationStripe stripe)
        if (
            isValid(activeDescriptor)
            && fromMaybe(?, activeDescriptor).mode == AsyncStripes
            && publishedUntil < fromMaybe(?, activeDescriptor).m
            && (
                !isValid(activeStripe)
                || !isValid(stripeLookahead)
            )
        );
        let descriptor = fromMaybe(?, activeDescriptor);
        UInt#(33) rowEndWide =
            zeroExtend(stripe.rowBegin)
            + zeroExtend(stripe.rowCount);
        dynamicAssert(stripe.rowCount > 0, "published stripe must be nonempty");
        dynamicAssert(
            stripe.stripeId == nextStripeId,
            "stripe publication ID mismatch"
        );
        dynamicAssert(
            stripe.rowBegin <= publishedUntil,
            "stripe publication gap"
        );
        dynamicAssert(
            stripe.rowBegin >= publishedUntil,
            "stripe publication overlap"
        );
        dynamicAssert(
            rowEndWide <= zeroExtend(descriptor.m),
            "stripe publication out of bounds"
        );
        dynamicAssert(
            stripe.rowCount <= descriptor.stripeRows,
            "stripe exceeds planned row count"
        );
        MatrixExtent rowEnd = truncate(rowEndWide);
        if (!isValid(activeStripe)) begin
            activeStripe <= tagged Valid stripe;
            macroNStart <= 0;
            iStart <= stripe.rowBegin;
            jStart <= 0;
        end
        else begin
            stripeLookahead <= tagged Valid stripe;
        end
        publishedUntil <= rowEnd;
        nextStripeId <= nextStripeId + 1;
    endmethod

    method Bool workValid =
        isValid(activeDescriptor)
        && isValid(activeStripe);

    method ArrayWork#(arrayDim) currentWork
        if (isValid(activeDescriptor) && isValid(activeStripe));
        return makeArrayWork(
            arrayDimension,
            fromMaybe(?, activeDescriptor),
            fromMaybe(?, activeStripe),
            macroNStart,
            iStart,
            jStart
        );
    endmethod

    method Action completeWork
        if (isValid(activeDescriptor) && isValid(activeStripe));
        let descriptor = fromMaybe(?, activeDescriptor);
        let stripe = fromMaybe(?, activeStripe);
        ArrayWork#(arrayDim) work = makeArrayWork(
            arrayDimension,
            descriptor,
            stripe,
            macroNStart,
            iStart,
            jStart
        );
        MatrixExtent stripeEnd = stripe.rowBegin + stripe.rowCount;
        MatrixExtent macroNCount = min(
            descriptor.macroNTileColumns,
            descriptor.n - macroNStart
        );
        MatrixExtent macroNEnd = macroNStart + macroNCount;
        MatrixExtent nextJ = jStart + zeroExtend(work.jCount);
        MatrixExtent nextI = iStart + zeroExtend(work.iCount);

        if (nextJ < macroNEnd) begin
            jStart <= nextJ;
        end
        else if (nextI < stripeEnd) begin
            iStart <= nextI;
            jStart <= macroNStart;
        end
        else if (macroNEnd < descriptor.n) begin
            macroNStart <= macroNEnd;
            iStart <= stripe.rowBegin;
            jStart <= macroNEnd;
        end
        else begin
            completions.enq(StripeCompletion {
                jobId: descriptor.jobId,
                stripeId: stripe.stripeId,
                completionContext: stripe.stripeContext
            });
            if (descriptor.mode == FullMatrix) begin
                if (isValid(stripeLookahead)) begin
                    let promoted = fromMaybe(?, stripeLookahead);
                    MatrixExtent followingBegin =
                        promoted.rowBegin + promoted.rowCount;
                    Maybe#(ActivationStripe) following = tagged Invalid;
                    if (followingBegin < descriptor.m) begin
                        following = tagged Valid makeFullStripe(
                            descriptor,
                            promoted.stripeId + 1,
                            followingBegin
                        );
                    end
                    activeStripe <= tagged Valid promoted;
                    stripeLookahead <= following;
                    macroNStart <= 0;
                    iStart <= promoted.rowBegin;
                    jStart <= 0;
                end
                else begin
                    activeStripe <= tagged Invalid;
                    activeDescriptor <= tagged Invalid;
                end
            end
            else begin
                if (isValid(stripeLookahead)) begin
                    let promoted = fromMaybe(?, stripeLookahead);
                    activeStripe <= tagged Valid promoted;
                    stripeLookahead <= tagged Invalid;
                    macroNStart <= 0;
                    iStart <= promoted.rowBegin;
                    jStart <= 0;
                end
                else begin
                    activeStripe <= tagged Invalid;
                end
                if (stripeEnd == descriptor.m) begin
                    dynamicAssert(
                        !isValid(stripeLookahead),
                        "final stripe cannot have lookahead"
                    );
                    activeDescriptor <= tagged Invalid;
                end
            end
        end
    endmethod

    method Bool lookaheadValid = isValid(stripeLookahead);

    method ActivationStripe lookaheadStripe
        if (isValid(stripeLookahead));
        return fromMaybe(?, stripeLookahead);
    endmethod

    method Bool completionValid = completions.notEmpty;

    method StripeCompletion completion if (completions.notEmpty);
        return completions.first;
    endmethod

    method Action consumeCompletion if (completions.notEmpty);
        completions.deq;
    endmethod
endmodule

endpackage
