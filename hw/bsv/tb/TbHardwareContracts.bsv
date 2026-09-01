package TbHardwareContracts;

import Assert::*;
import AquaLocalAddr::*;
import AquaTypes::*;
import AquaWorkTypes::*;

(* synthesize *)
module mkTbHardwareContracts(Empty);
    staticAssert(valueOf(AquaBlockSize) == 32, "AQuA block size mismatch");
    staticAssert(valueOf(SizeOf#(MatrixExtent)) == 32, "matrix extent width mismatch");
    staticAssert(valueOf(SizeOf#(MatmulJobId)) == 32, "job ID width mismatch");
    staticAssert(valueOf(SizeOf#(HostTensorId)) == 32, "tensor ID width mismatch");
    staticAssert(valueOf(SizeOf#(StripeId)) == 32, "stripe ID width mismatch");
    staticAssert(valueOf(SizeOf#(ArrayWorkId)) == 32, "array work ID width mismatch");
    staticAssert(valueOf(SizeOf#(KFragmentId)) == 32, "fragment ID width mismatch");
    staticAssert(valueOf(SizeOf#(AquaMemoryTxnId)) == 40, "memory transaction ID width mismatch");
    staticAssert(valueOf(SizeOf#(ArrayCount)) == 7, "array count width mismatch");

    rule verify;
        ExecuteWork#(16) execute = ExecuteWork {
            jobId: 1,
            stripeId: 2,
            arrayWorkId: 3,
            fragmentId: 4,
            iStart: 5,
            iCount: 6,
            jStart: 7,
            jCount: 8,
            fragmentKStart: 9,
            fragmentKCount: 10,
            fragmentBlockIndex: 11,
            fragmentEndsBlock: True,
            activationBase: AquaLocalAddr {
                region: LocalActivation,
                bank: 1,
                row: 2
            },
            weightBase: AquaLocalAddr {
                region: LocalWeight,
                bank: 3,
                row: 4
            },
            blockShiftAddress: AquaLocalAddr {
                region: LocalHp1Meta,
                bank: 5,
                row: 6
            },
            rowShiftAddress: AquaLocalAddr {
                region: LocalHp1Meta,
                bank: 7,
                row: 8
            },
            accumulatorBase: AquaLocalAddr {
                region: LocalAccumulator,
                bank: 9,
                row: 10
            },
            accumulate: True
        };
        ExecuteWork#(16) restoredExecute = unpack(pack(execute));
        ExecuteCompletion completion = ExecuteCompletion {
            jobId: 12,
            stripeId: 13,
            arrayWorkId: 14,
            fragmentId: 15
        };
        ExecuteCompletion restoredCompletion = unpack(pack(completion));

        dynamicAssert(
            restoredExecute == execute,
            "execute work pack round trip"
        );
        dynamicAssert(
            restoredCompletion == completion,
            "execute completion pack round trip"
        );
        dynamicAssert(aquaBlockSize == 32, "runtime block size mismatch");
        $display("PASS mkTbHardwareContracts");
        $finish(0);
    endrule
endmodule

endpackage
