package AquaTypes;

typedef 32 AquaBlockSize;
Integer aquaBlockSize = valueOf(AquaBlockSize);

typedef UInt#(32) MatrixExtent; // 행렬 크기, 좌표 또는 원소 개수.
typedef UInt#(32) MatmulJobId; // 전체 matrix multiplication 작업 ID.
typedef UInt#(32) HostTensorId; // Host/runtime이 소유하는 tensor ID.
typedef UInt#(32) StripeId; // Activation stripe ID.
typedef UInt#(32) MacroTileId; // Macro tile ID.
typedef UInt#(32) ArrayWorkId; // Physical systolic-array work ID.
typedef UInt#(32) KFragmentId; // K 방향 실행 fragment ID.
typedef UInt#(40) AquaMemoryTxnId; // 개별 memory transaction ID.
typedef UInt#(16) LocalSlotId; // Local-memory residency slot ID.

// 하나의 HP1 K-block에 적용되는 실행용 block-scale metadata.
typedef struct {
    Bool zeroBlock;                 // True이면 block 전체 contribution이 0.
    UInt#(shiftWidth) leftShift;    // Integer partial sum에 적용할 LEFT SHIFT.
} Hp1BlockScale#(numeric type shiftWidth)
    deriving (Bits, Eq, FShow);


// ============================================================================
// Notes
// ============================================================================
//
// ID hierarchy
// ------------
//
// MatmulJobId
//   └─ StripeId
//       └─ MacroTileId
//           └─ ArrayWorkId
//               └─ KFragmentId
//
// AquaMemoryTxnId는 위 execution hierarchy와 별개로,
// 각 activation/weight/metadata/output memory transaction을 식별한다.
//
// LocalSlotId는 향후 current/next tile residency와 double buffering을
// 표현하기 위한 local-memory slot 식별자다.
//
//
// Hp1BlockScale
// -------------
//
// HP1 weight는 block-relative power-of-two scale을 사용한다.
//
//     W = q × 2^m × channel_scale
//
// 여기서 q는 int8 weight code이고, m은 32-element K-block마다
// 공유되는 block scale이다.
//
// Hardware에서는 먼저 integer dot product를 계산한 뒤:
//
//     partial = sum(activation_q * weight_q)
//
// block scale을 multiplier가 아니라 LEFT SHIFT로 적용한다.
//
//     scaledPartial = partial << m
//
// 이후 모든 K-block contribution을 accumulator에 더하고,
// 마지막 row/channel scale은 별도의 RIGHT SHIFT로 적용한다.
//
//     output = accumulator >> rowRightShift
//
// 따라서 Hp1BlockScale은 float scale 자체가 아니라:
//
//     ZeroBlock
//
// 또는
//
//     LeftShift(m)
//
// 을 표현하는 hardware execution metadata다.
//
// Q8_HP1 GGUF의 zero block은 m == i16::MIN sentinel을 사용하지만,
// BSV datapath에서는 이 값을 직접 전달하지 않고 zeroBlock Bool로
// 의미를 명시적으로 표현한다.
//
// shiftWidth는 synthesis-time parameter다.
// 현재 GPT-2에서는 block shift 0..9가 관측되어 4 bit면 충분하지만,
// 지원 모델 전체의 범위를 확인하기 전까지 width를 고정하지 않는다.

endpackage