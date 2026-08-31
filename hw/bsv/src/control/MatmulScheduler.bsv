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


// 현재 stripe와 N macro tile 안에서 하나의 DIM-bounded ArrayWork를 생성한다.
function ArrayWork#(arrayDim) makeArrayWork(
    MatrixExtent arrayDimension,
    AquaMatmulDescriptor descriptor,
    ActivationStripe stripe,
    MatrixExtent macroNStart,
    MatrixExtent iStart,
    MatrixExtent jStart
);

    // 현재 stripe의 마지막 M row 다음 위치.
    MatrixExtent stripeEnd = stripe.rowBegin + stripe.rowCount;

    // 마지막 N macro tile이 matrix N 경계를 넘지 않도록 실제 column 수를 제한한다.
    MatrixExtent macroNCount = min(
        descriptor.macroNTileColumns,
        descriptor.n - macroNStart
    );

    // 현재 N macro tile의 마지막 column 다음 위치.
    MatrixExtent macroNEnd = macroNStart + macroNCount;

    // 이번 physical array work가 처리할 실제 M row 수.
    MatrixExtent iCount = min(
        arrayDimension,
        stripeEnd - iStart
    );

    // 이번 physical array work가 처리할 실제 N/J column 수.
    MatrixExtent jCount = min(
        arrayDimension,
        macroNEnd - jStart
    );

    return ArrayWork {
        jobId: descriptor.jobId,
        stripeId: stripe.stripeId,

        // 이번 array work가 시작하는 global M/N 좌표.
        iStart: iStart,
        jStart: jStart,

        // iCount/jCount는 항상 arrayDim 이하이므로 ArrayCount로 축소한다.
        iCount: truncate(iCount),
        jCount: truncate(jCount),

        // AquaLoopMatmul이 아직 없으므로 현재는 logical K 전체를 하나의 range로 사용한다.
        kTileStart: 0,
        kTileCount: descriptor.k
    };

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
// Current K behavior
// ------------------
//
// 현재 makeArrayWork()는:
//
//     kTileStart = 0
//     kTileCount = descriptor.k
//
// 로 logical K 전체를 ArrayWork의 K range로 전달한다.
//
// 이 full-K range는 이후 WorkScheduler가:
//
//     array dimension
//     AQuA block boundary = 32
//
// 를 기준으로 실제 KFragment들로 다시 나눈다.
//
// 즉 현재 단계에서는:
//
//     ArrayWork
//         K = full logical K
//             ↓
//     WorkScheduler
//             ↓
//         KFragment
//
// 구조다.
//
// 향후 AquaLoopMatmul이 구현되면:
//
//     macroKStart
//     macroKCount
//
// 단위로 ArrayWork의 kTileStart/kTileCount를 공급하도록 변경된다.

endpackage
