package TbAquaLoopAccumulatorMapping;

import Assert::*;
import AquaLocalAddr::*;
import AquaTypes::*;
import AquaWorkTypes::*;
import AquaLoopMatmul::*;

function ArrayWork#(16) mappedWork(MatrixExtent kTileStart);
    return ArrayWork {
        jobId: 1,
        stripeId: 2,
        stripeRowBegin: 100,
        macroNStart: 24,
        macroNCount: 40,
        iStart: 116,
        jStart: 56,
        iCount: 16,
        jCount: 8,
        kTileStart: kTileStart,
        kTileCount: 32
    };
endfunction

(* synthesize *)
module mkTbAquaLoopAccumulatorMapping(Empty);
    rule verify;
        ArrayWork#(16) first = mappedWork(0);
        ArrayWork#(16) later = mappedWork(32);
        ArrayWork#(16) overflow = ArrayWork {
            jobId: 3,
            stripeId: 4,
            stripeRowBegin: 0,
            macroNStart: 0,
            macroNCount: 65536,
            iStart: 65520,
            jStart: 65520,
            iCount: 16,
            jCount: 16,
            kTileStart: 0,
            kTileCount: 16
        };

        let firstBase = accumulatorBase(first, 16);
        let laterBase = accumulatorBase(later, 16);
        dynamicAssert(
            accumulatorBaseValid(first, 16),
            "mapped accumulator base valid"
        );
        dynamicAssert(
            firstBase.region == LocalAccumulator,
            "mapped accumulator region"
        );
        dynamicAssert(firstBase.bank == 0, "mapped accumulator bank");
        dynamicAssert(firstBase.row == 80, "mapped accumulator row");
        dynamicAssert(
            laterBase == firstBase,
            "macro K accumulator mapping changed"
        );
        dynamicAssert(
            !accumulatorBaseValid(overflow, 16),
            "overflowing accumulator mapping accepted"
        );
        $display("PASS: mkTbAquaLoopAccumulatorMapping");
        $finish(0);
    endrule
endmodule

endpackage
