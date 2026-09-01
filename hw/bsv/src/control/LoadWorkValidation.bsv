package LoadWorkValidation;

import Assert::*;
import AquaLocalAddr::*;
import AquaMemoryTypes::*;

function Action validateProviderLoadWork(
    ProviderLoadWork#(arrayDim) work,
    Integer bankCount,
    Integer metaEntries
) provisos (
    Add#(arrayPadding, TLog#(TAdd#(arrayDim, 1)), 32)
);
    action
        UInt#(32) iCount = zeroExtend(work.iCount);
        UInt#(32) jCount = zeroExtend(work.jCount);
        UInt#(33) iEnd = zeroExtend(work.iStart) + zeroExtend(iCount);
        UInt#(33) jEnd = zeroExtend(work.jStart) + zeroExtend(jCount);
        UInt#(33) kEnd =
            zeroExtend(work.fragmentKStart)
            + zeroExtend(work.fragmentKCount);
        UInt#(32) activationBaseBank =
            zeroExtend(unpack(work.activationBase.bank));
        UInt#(32) activationBaseRow =
            zeroExtend(unpack(work.activationBase.row));
        UInt#(32) weightBaseBank =
            zeroExtend(unpack(work.weightBase.bank));
        UInt#(32) weightBaseRow =
            zeroExtend(unpack(work.weightBase.row));
        UInt#(40) activationLinearEnd =
            zeroExtend(activationBaseRow) * fromInteger(bankCount)
            + zeroExtend(activationBaseBank)
            + zeroExtend(iCount == 0 ? 0 : iCount - 1);
        UInt#(40) weightLinearEnd =
            zeroExtend(weightBaseRow) * fromInteger(bankCount)
            + zeroExtend(weightBaseBank)
            + zeroExtend(jCount == 0 ? 0 : jCount - 1);
        UInt#(32) blockMetadataBank =
            zeroExtend(unpack(work.blockShiftDestination.bank));
        UInt#(32) blockMetadataRow =
            zeroExtend(unpack(work.blockShiftDestination.row));
        UInt#(32) rowMetadataBank =
            zeroExtend(unpack(work.rowScaleDestination.bank));
        UInt#(32) rowMetadataRow =
            zeroExtend(unpack(work.rowScaleDestination.row));

        dynamicAssert(work.iCount > 0, "load work I count must be positive");
        dynamicAssert(work.jCount > 0, "load work J count must be positive");
        dynamicAssert(work.fragmentKCount > 0,
                      "load fragment K count must be positive");
        dynamicAssert(work.iCount <= fromInteger(valueOf(arrayDim)),
                      "load work I count exceeds array dimension");
        dynamicAssert(work.jCount <= fromInteger(valueOf(arrayDim)),
                      "load work J count exceeds array dimension");
        dynamicAssert(work.fragmentKCount <= fromInteger(valueOf(arrayDim)),
                      "load fragment K count exceeds array dimension");
        dynamicAssert(iEnd <= fromInteger(2 ** 32 - 1),
                      "load work I range overflow");
        dynamicAssert(jEnd <= fromInteger(2 ** 32 - 1),
                      "load work J range overflow");
        dynamicAssert(kEnd <= fromInteger(2 ** 32 - 1),
                      "load work K range overflow");
        dynamicAssert(work.activationBase.region == LocalActivation,
                      "activation base has wrong local region");
        dynamicAssert(work.weightBase.region == LocalWeight,
                      "weight base has wrong local region");
        dynamicAssert(activationBaseBank < fromInteger(bankCount),
                      "activation base bank exceeds configured banks");
        dynamicAssert(weightBaseBank < fromInteger(bankCount),
                      "weight base bank exceeds configured banks");
        dynamicAssert(
            activationLinearEnd / fromInteger(bankCount)
                < fromInteger(2 ** 16),
            "activation local row range overflow"
        );
        dynamicAssert(
            weightLinearEnd / fromInteger(bankCount)
                < fromInteger(2 ** 16),
            "weight local row range overflow"
        );
        dynamicAssert(work.blockShiftDestination.region == LocalHp1Meta,
                      "block shift has wrong local region");
        dynamicAssert(work.rowScaleDestination.region == LocalHp1Meta,
                      "row scale has wrong local region");
        dynamicAssert(blockMetadataBank == 0,
                      "block shift metadata bank must be zero");
        dynamicAssert(rowMetadataBank == 0,
                      "row scale metadata bank must be zero");
        dynamicAssert(blockMetadataRow < fromInteger(metaEntries),
                      "block shift metadata row out of bounds");
        dynamicAssert(rowMetadataRow < fromInteger(metaEntries),
                      "row scale metadata row out of bounds");
    endaction
endfunction

endpackage
