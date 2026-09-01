package AquaLocalAddr;

typedef enum {
    LocalActivation,
    LocalWeight,
    LocalHp1Meta,
    LocalAccumulator,
    LocalExsiaStripe,
    LocalRaco
} AquaLocalRegion deriving (Bits, Eq, FShow);

typedef struct {
    AquaLocalRegion region;
    Bit#(slotWidth) slot;
    Bit#(bankWidth) bank;
    Bit#(rowWidth) row;
} AquaLocalAddr#(
    numeric type slotWidth,
    numeric type bankWidth,
    numeric type rowWidth
) deriving (Bits, Eq, FShow);

typedef struct {
    Bit#(bankWidth) bank;
    Bit#(rowWidth) row;
} AquaBankedRow#(
    numeric type bankWidth,
    numeric type rowWidth
) deriving (Bits, Eq, FShow);

function AquaBankedRow#(bankWidth, rowWidth) mapGlobalRow(
    UInt#(32) globalRow,
    Integer bankCount
) provisos (
    Add#(bankPadding, bankWidth, 32),
    Add#(rowPadding, rowWidth, 32)
);
    if (bankCount <= 0) begin
        return error("bank count must be positive");
    end
    else if (bankCount > (2 ** valueOf(bankWidth))) begin
        return error("bank count exceeds bank address width");
    end
    else begin
        UInt#(32) localRow = globalRow / fromInteger(bankCount);
        UInt#(33) localRowWide = zeroExtend(localRow);
        if (localRowWide >= fromInteger(2 ** valueOf(rowWidth))) begin
            return error("global row exceeds local row address width");
        end
        else begin
            Bit#(bankWidth) bank = truncate(pack(globalRow % fromInteger(bankCount)));
            Bit#(rowWidth) row = truncate(pack(localRow));
            return AquaBankedRow { bank: bank, row: row };
        end
    end
endfunction

endpackage
