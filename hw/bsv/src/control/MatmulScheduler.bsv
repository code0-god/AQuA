package MatmulScheduler;

import Assert::*;
import FIFOF::*;
import AquaLocalAddr::*;
import AquaTypes::*;
import AquaWorkTypes::*;

// FullMatrix mode에서 하나의 activation stripe를 생성한다.
function ActivationStripe makeFullStripe(
    AquaMatmulDescriptor descriptor,
    StripeId stripeId,
    MatrixExtent rowBegin
);

    // 마지막 stripe가 M 경계를 넘지 않도록 실제 row 수를 제한한다.
    MatrixExtent rowCount = min(
        descriptor.stripeRows,
        descriptor.m - rowBegin
    );

    // Local activation memory의 시작 주소를 사용한다.
    AquaLocalAddr base = AquaLocalAddr {
        region: LocalActivation,
        bank: 0,
        row: 0
    };

    // 계산된 row 범위와 local-memory base를 stripe descriptor로 반환한다.
    return ActivationStripe {
        stripeId: stripeId,
        rowBegin: rowBegin,
        rowCount: rowCount,
        activationBase: base,
        stripeContext: descriptor.jobContext
    };

endfunction


typedef struct {
    MatrixExtent macroNStart;
    MatrixExtent macroKStart;
    MatrixExtent iStart;
    MatrixExtent jStart;
} WorkPosition deriving (Bits, Eq, FShow);

function MatrixExtent stripeRowEnd(ActivationStripe stripe);
    return stripe.rowBegin + stripe.rowCount;
endfunction

function MatrixExtent macroNCount(
    AquaMatmulDescriptor descriptor,
    MatrixExtent macroNStart
);
    return min(
        descriptor.macroNTileColumns,
        descriptor.n - macroNStart
    );
endfunction

function MatrixExtent macroNEnd(
    AquaMatmulDescriptor descriptor,
    MatrixExtent macroNStart
);
    return macroNStart + macroNCount(descriptor, macroNStart);
endfunction

function MatrixExtent macroKCount(
    AquaMatmulDescriptor descriptor,
    MatrixExtent macroKStart
);
    return min(
        descriptor.macroKTileElements,
        descriptor.k - macroKStart
    );
endfunction

function MatrixExtent macroKEnd(
    AquaMatmulDescriptor descriptor,
    MatrixExtent macroKStart
);
    return macroKStart + macroKCount(descriptor, macroKStart);
endfunction


// 현재 stripe와 N macro tile 안에서 하나의 DIM-bounded ArrayWork를 생성한다.
function ArrayWork#(arrayDim) makeArrayWork(
    MatrixExtent arrayDimension,
    AquaMatmulDescriptor descriptor,
    ActivationStripe stripe,
    WorkPosition position
);

    // 현재 stripe의 마지막 M row 다음 위치.
    MatrixExtent stripeEnd = stripeRowEnd(stripe);

    // 마지막 N macro tile이 matrix N 경계를 넘지 않도록 실제 column 수를 제한한다.
    MatrixExtent macroTileEnd =
        macroNEnd(descriptor, position.macroNStart);
    MatrixExtent currentMacroNCount =
        macroNCount(descriptor, position.macroNStart);

    // 이번 physical array work가 처리할 실제 M row 수.
    MatrixExtent iCount = min(
        arrayDimension,
        stripeEnd - position.iStart
    );

    // 이번 physical array work가 처리할 실제 N/J column 수.
    MatrixExtent jCount = min(
        arrayDimension,
        macroTileEnd - position.jStart
    );

    return ArrayWork {
        jobId: descriptor.jobId,
        stripeId: stripe.stripeId,

        stripeRowBegin: stripe.rowBegin,
        macroNStart: position.macroNStart,
        macroNCount: currentMacroNCount,

        // 이번 array work가 시작하는 global M/N 좌표.
        iStart: position.iStart,
        jStart: position.jStart,

        // iCount/jCount는 항상 arrayDim 이하이므로 ArrayCount로 축소한다.
        iCount: truncate(iCount),
        jCount: truncate(jCount),

        kTileStart: position.macroKStart,
        kTileCount: macroKCount(descriptor, position.macroKStart)
    };

endfunction


function Maybe#(WorkPosition) nextWorkPosition(
    AquaMatmulDescriptor descriptor,
    ActivationStripe stripe,
    WorkPosition current,
    ArrayWork#(arrayDim) work
);
    MatrixExtent stripeEnd = stripeRowEnd(stripe);
    MatrixExtent macroTileEnd =
        macroNEnd(descriptor, current.macroNStart);
    MatrixExtent currentMacroKEnd =
        macroKEnd(descriptor, current.macroKStart);
    MatrixExtent nextJ =
        current.jStart + zeroExtend(work.jCount);
    MatrixExtent nextI =
        current.iStart + zeroExtend(work.iCount);

    if (nextJ < macroTileEnd) begin
        return tagged Valid WorkPosition {
            macroNStart: current.macroNStart,
            macroKStart: current.macroKStart,
            iStart: current.iStart,
            jStart: nextJ
        };
    end
    else if (nextI < stripeEnd) begin
        return tagged Valid WorkPosition {
            macroNStart: current.macroNStart,
            macroKStart: current.macroKStart,
            iStart: nextI,
            jStart: current.macroNStart
        };
    end
    else if (currentMacroKEnd < descriptor.k) begin
        return tagged Valid WorkPosition {
            macroNStart: current.macroNStart,
            macroKStart: currentMacroKEnd,
            iStart: stripe.rowBegin,
            jStart: current.macroNStart
        };
    end
    else if (macroTileEnd < descriptor.n) begin
        return tagged Valid WorkPosition {
            macroNStart: macroTileEnd,
            macroKStart: 0,
            iStart: stripe.rowBegin,
            jStart: macroTileEnd
        };
    end
    else begin
        return tagged Invalid;
    end
endfunction

function Bool validDescriptor(AquaMatmulDescriptor descriptor);
    return
        descriptor.m > 0
        && descriptor.n > 0
        && descriptor.k > 0
        && descriptor.stripeRows > 0
        && descriptor.stripeRows <= descriptor.m
        && descriptor.macroNTileColumns > 0
        && descriptor.macroNTileColumns <= descriptor.n
        && descriptor.macroKTileElements > 0
        && descriptor.macroKTileElements <= descriptor.k;
endfunction

function Bool validPublishedStripe(
    AquaMatmulDescriptor descriptor,
    ActivationStripe stripe,
    StripeId expectedStripeId,
    MatrixExtent publishedUntil
);
    return
        stripe.stripeId == expectedStripeId
        && stripe.rowBegin == publishedUntil
        && stripe.rowCount > 0
        && stripe.rowCount <= descriptor.stripeRows
        && stripe.rowBegin < descriptor.m
        && stripe.rowCount <= descriptor.m - stripe.rowBegin;
endfunction


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

module mkMatmulScheduler(MatmulSchedulerIfc#(arrayDim));

    FIFOF#(StripeCompletion) completions <- mkSizedFIFOF(2);
    Reg#(Maybe#(AquaMatmulDescriptor)) activeDescriptor
        <- mkReg(tagged Invalid);
    Reg#(Maybe#(ActivationStripe)) activeStripe
        <- mkReg(tagged Invalid);
    Reg#(Maybe#(ActivationStripe)) stripeLookahead
        <- mkReg(tagged Invalid);
    Reg#(WorkPosition) workPosition <- mkReg(WorkPosition {
        macroNStart: 0,
        macroKStart: 0,
        iStart: 0,
        jStart: 0
    });
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
        Bool valid = validDescriptor(descriptor);
        dynamicAssert(
            descriptor.macroKTileElements > 0,
            "macro K tile must be nonempty"
        );
        dynamicAssert(
            descriptor.macroKTileElements <= descriptor.k,
            "macro K tile exceeds logical K"
        );
        dynamicAssert(valid, "invalid matmul descriptor");

        if (valid) begin
            activeDescriptor <= tagged Valid descriptor;
            publishedUntil <= 0;
            nextStripeId <= 0;
            workPosition <= WorkPosition {
                macroNStart: 0,
                macroKStart: 0,
                iStart: 0,
                jStart: 0
            };

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
        Bool valid = validPublishedStripe(
            descriptor,
            stripe,
            nextStripeId,
            publishedUntil
        );
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
        if (valid) begin
            MatrixExtent rowEnd = stripe.rowBegin + stripe.rowCount;
            if (!isValid(activeStripe)) begin
                activeStripe <= tagged Valid stripe;
                workPosition <= WorkPosition {
                    macroNStart: 0,
                    macroKStart: 0,
                    iStart: stripe.rowBegin,
                    jStart: 0
                };
            end
            else begin
                stripeLookahead <= tagged Valid stripe;
            end
            publishedUntil <= rowEnd;
            nextStripeId <= nextStripeId + 1;
        end
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
            workPosition
        );
    endmethod

    method Action completeWork
        if (isValid(activeDescriptor) && isValid(activeStripe));
        let descriptor = fromMaybe(?, activeDescriptor);
        let stripe = fromMaybe(?, activeStripe);
        let position = workPosition;
        ArrayWork#(arrayDim) work = makeArrayWork(
            arrayDimension,
            descriptor,
            stripe,
            position
        );
        Maybe#(WorkPosition) next = nextWorkPosition(
            descriptor,
            stripe,
            position,
            work
        );

        if (isValid(next)) begin
            workPosition <= fromMaybe(?, next);
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
                    workPosition <= WorkPosition {
                        macroNStart: 0,
                        macroKStart: 0,
                        iStart: promoted.rowBegin,
                        jStart: 0
                    };
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
                    workPosition <= WorkPosition {
                        macroNStart: 0,
                        macroKStart: 0,
                        iStart: promoted.rowBegin,
                        jStart: 0
                    };
                end
                else begin
                    activeStripe <= tagged Invalid;
                end
                if (
                    stripe.rowBegin + stripe.rowCount
                    == descriptor.m
                ) begin
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


// ============================================================================
// Notes
// ============================================================================
//
// makeFullStripe
// --------------
//
// 전체 M dimension을 descriptor.stripeRows 크기로 나눌 때 하나의
// ActivationStripe를 생성한다.
//
// 예:
//
//     M = 150
//     stripeRows = 64
//
//     stripe 0:
//         rowBegin = 0
//         rowCount = 64
//
//     stripe 1:
//         rowBegin = 64
//         rowCount = 64
//
//     stripe 2:
//         rowBegin = 128
//         rowCount = 22
//
// 따라서:
//
//     rowCount = min(stripeRows, M - rowBegin)
//
// 이 된다.
//
// activationBase는 현재 stripe가 사용할 LocalActivation 영역의 시작 주소다.
//
// makeArrayWork
// -------------
//
// 하나의 stripe와 하나의 macro N tile을 physical systolic-array 크기에
// 맞는 ArrayWork로 자른다.
//
// 예:
//
//     DIM = 16
//     stripe rows = 17
//     macro N columns = 18
//
// 가능한 ArrayWork:
//
//     I 0..15 / J 0..15
//     I 0..15 / J 16..17
//     I 16    / J 0..15
//     I 16    / J 16..17
//
// iCount와 jCount는 matrix/stripe의 마지막 edge에서는 DIM보다 작아진다.
//
//
// macroNCount
// -----------
//
// descriptor.macroNTileColumns보다 matrix의 남은 N column이 적을 수 있으므로:
//
//     macroNCount = min(
//         macroNTileColumns,
//         N - macroNStart
//     )
//
// 으로 마지막 partial macro N tile을 만든다.
//
//
// ArrayCount
// ----------
//
// iCount와 jCount의 실제 계산은 MatrixExtent(UInt#(32))로 수행하지만,
// ArrayWork 내부에서는 7-bit ArrayCount로 저장한다.
//
// 지원하는 DIM 16/32/64와 0..64 범위를 모두 표현할 수 있다.
//
//
// macro-K behavior
// ----------------
//
// kTileStart와 kTileCount는 현재 macro-K tile의 실제 logical K 범위다.
// WorkScheduler는 이 범위를 DIM 및 AQuA block 경계로 다시 분할한다.

endpackage
