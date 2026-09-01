package MatmulScheduleMath;

import AquaLocalAddr::*;
import AquaMath::*;
import AquaTypes::*;
import AquaWorkTypes::*;

function ActivationStripe makeFullStripe(
    AquaMatmulDescriptor descriptor,
    StripeId stripeId,
    MatrixExtent rowBegin
);
    MatrixExtent rowCount = min(
        descriptor.stripeRows,
        descriptor.m - rowBegin
    );
    DefaultAquaLocalAddr base = DefaultAquaLocalAddr {
        region: LocalActivation,
        slot: truncate(pack(stripeId)),
        bank: 0,
        row: 0
    };
    return ActivationStripe {
        stripeId: stripeId,
        rowBegin: rowBegin,
        rowCount: rowCount,
        activationBase: base,
        stripeContext: descriptor.jobContext
    };
endfunction

function ArrayWork#(arrayDim) makeArrayWork(
    MatrixExtent arrayDimension,
    AquaMatmulDescriptor descriptor,
    ActivationStripe stripe,
    MatrixExtent macroNStart,
    MatrixExtent iStart,
    MatrixExtent jStart
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32)
);
    MatrixExtent stripeEnd = stripe.rowBegin + stripe.rowCount;
    MatrixExtent macroNCount = min(
        descriptor.macroNTileColumns,
        descriptor.n - macroNStart
    );
    MatrixExtent macroNEnd = macroNStart + macroNCount;
    MatrixExtent iCount = min(arrayDimension, stripeEnd - iStart);
    MatrixExtent jCount = min(arrayDimension, macroNEnd - jStart);
    LocalSlotId slot = unpack(zeroExtend(stripe.activationBase.slot));
    return ArrayWork {
        jobId: descriptor.jobId,
        stripeId: stripe.stripeId,
        iStart: iStart,
        jStart: jStart,
        iCount: truncate(iCount),
        jCount: truncate(jCount),
        // AquaLoopMatmul is deferred, so the current descriptor is one
        // explicit full-K macro range in this phase.
        kTileStart: 0,
        kTileCount: descriptor.k,
        slot: slot
    };
endfunction

endpackage
