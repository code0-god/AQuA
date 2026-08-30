package AquaTypes;

typedef UInt#(32) MatrixExtent;
typedef UInt#(32) MatmulJobId;
typedef UInt#(32) HostTensorId;
typedef UInt#(32) StripeId;
typedef UInt#(16) LocalSlotId;

typedef struct {
    Bool zeroBlock;
    UInt#(shiftWidth) leftShift;
} Hp1BlockScale#(numeric type shiftWidth) deriving (Bits, Eq, FShow);

endpackage
