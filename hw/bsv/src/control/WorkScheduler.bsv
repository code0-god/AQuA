package WorkScheduler;

import Assert::*;
import AquaTypes::*;
import AquaWorkTypes::*;

interface WorkSchedulerIfc#(numeric type arrayDim);
    method Bool startReady;
    method Action start(ArrayWork#(arrayDim) work, Bool priorAccumulation);

    method Bool fragmentValid;
    method KFragment currentFragment;
    method Action consumeFragment;

    method Bool lookaheadValid;
    method KFragment lookaheadFragment;

    method Bool doneValid;
    method Action consumeDone;
endinterface

function KFragment makeFragment(
    MatrixExtent arrayDimension,
    ArrayWork#(arrayDim) work,
    MatrixExtent fragmentStart,
    Bool accumulate
);
    MatrixExtent workEnd = work.kTileStart + work.kTileCount;
    MatrixExtent remaining = workEnd - fragmentStart;
    MatrixExtent blockSize = fromInteger(aquaBlockSize);
    MatrixExtent remainingInBlock =
        blockSize - (fragmentStart % blockSize);
    MatrixExtent count = min(
        arrayDimension,
        min(remaining, remainingInBlock)
    );
    MatrixExtent fragmentEnd = fragmentStart + count;
    return KFragment {
        jobId: work.jobId,
        stripeId: work.stripeId,
        fragmentKStart: fragmentStart,
        fragmentKCount: truncate(count),
        fragmentBlockIndex: fragmentStart / blockSize,
        fragmentEndsBlock: fragmentEnd % blockSize == 0,
        accumulate: accumulate
    };
endfunction

module mkWorkScheduler(WorkSchedulerIfc#(arrayDim));
    Reg#(Maybe#(ArrayWork#(arrayDim))) activeWork <- mkReg(tagged Invalid);
    Reg#(Maybe#(KFragment)) current <- mkReg(tagged Invalid);
    Reg#(Maybe#(KFragment)) lookahead <- mkReg(tagged Invalid);
    Reg#(Bool) done <- mkReg(False);

    MatrixExtent arrayDimension = fromInteger(valueOf(arrayDim));

    method Bool startReady = !isValid(activeWork) && !done;

    method Action start(ArrayWork#(arrayDim) work, Bool priorAccumulation)
        if (!isValid(activeWork) && !done);
        UInt#(33) workEndWide =
            zeroExtend(work.kTileStart) + zeroExtend(work.kTileCount);
        MatrixExtent workEnd = truncate(workEndWide);
        Bool valid =
            work.kTileCount > 0
            && workEndWide <= fromInteger(2 ** 32 - 1)
            && work.iCount > 0
            && work.jCount > 0
            && zeroExtend(work.iCount) <= arrayDimension
            && zeroExtend(work.jCount) <= arrayDimension;
        dynamicAssert(work.kTileCount > 0, "macro K tile must be nonempty");
        dynamicAssert(
            workEndWide <= fromInteger(2 ** 32 - 1),
            "macro K tile range overflow"
        );
        dynamicAssert(work.iCount > 0, "array I count must be positive");
        dynamicAssert(work.jCount > 0, "array J count must be positive");
        dynamicAssert(
            zeroExtend(work.iCount) <= arrayDimension,
            "array I count exceeds DIM"
        );
        dynamicAssert(
            zeroExtend(work.jCount) <= arrayDimension,
            "array J count exceeds DIM"
        );

        if (valid) begin
            KFragment first = makeFragment(
                arrayDimension,
                work,
                work.kTileStart,
                priorAccumulation
            );
            MatrixExtent nextStart =
                first.fragmentKStart + zeroExtend(first.fragmentKCount);
            Maybe#(KFragment) next = tagged Invalid;
            if (nextStart < workEnd) begin
                next = tagged Valid makeFragment(
                    arrayDimension,
                    work,
                    nextStart,
                    True
                );
            end

            activeWork <= tagged Valid work;
            current <= tagged Valid first;
            lookahead <= next;
        end
    endmethod

    method Bool fragmentValid = isValid(current);

    method KFragment currentFragment if (isValid(current));
        return fromMaybe(?, current);
    endmethod

    method Action consumeFragment if (isValid(current));
        let work = fromMaybe(?, activeWork);
        let next = lookahead;
        if (isValid(next)) begin
            let promoted = fromMaybe(?, next);
            MatrixExtent followingStart =
                promoted.fragmentKStart + zeroExtend(promoted.fragmentKCount);
            MatrixExtent workEnd =
                work.kTileStart + work.kTileCount;
            Maybe#(KFragment) following = tagged Invalid;
            if (followingStart < workEnd) begin
                following = tagged Valid makeFragment(
                    arrayDimension,
                    work,
                    followingStart,
                    True
                );
            end
            current <= tagged Valid promoted;
            lookahead <= following;
        end
        else begin
            current <= tagged Invalid;
            activeWork <= tagged Invalid;
            done <= True;
        end
    endmethod

    method Bool lookaheadValid = isValid(lookahead);

    method KFragment lookaheadFragment if (isValid(lookahead));
        return fromMaybe(?, lookahead);
    endmethod

    method Bool doneValid = done;

    method Action consumeDone if (done);
        done <= False;
    endmethod
endmodule

endpackage
