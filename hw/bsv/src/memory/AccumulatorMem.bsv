package AccumulatorMem;

import Assert::*;
import FIFOF::*;
import RegFile::*;
import SpecialFIFOs::*;
import Vector::*;

typedef Bit#(TLog#(TAdd#(banks, 1))) AccumulatorBank#(numeric type banks);
typedef Bit#(TLog#(TAdd#(rows, 1))) AccumulatorRow#(numeric type rows);

typedef struct {
    AccumulatorBank#(banks) bank;
    AccumulatorRow#(rows) row;
} AccumulatorReadReq#(
    numeric type banks,
    numeric type rows
) deriving (Bits, Eq, FShow);

typedef struct {
    AccumulatorBank#(banks) bank;
    AccumulatorRow#(rows) row;
    Int#(accWidth) value;
} AccumulatorReadResponse#(
    numeric type banks,
    numeric type rows,
    numeric type accWidth
) deriving (Bits, Eq, FShow);

typedef struct {
    AccumulatorBank#(banks) bank;
    AccumulatorRow#(rows) row;
} AccumulatorWriteCompletion#(
    numeric type banks,
    numeric type rows
) deriving (Bits, Eq, FShow);

typedef struct {
    AccumulatorBank#(banks) bank;
    AccumulatorRow#(rows) row;
    Int#(accWidth) value;
} AccumulatorPendingWrite#(
    numeric type banks,
    numeric type rows,
    numeric type accWidth
) deriving (Bits, Eq, FShow);

interface AccumulatorMemIfc#(
    numeric type banks,
    numeric type rows,
    numeric type accWidth
);
    method Bool readReady;
    method Action requestRead(
        AccumulatorBank#(banks) bank,
        AccumulatorRow#(rows) row
    );
    method Bool readValid;
    method AccumulatorReadResponse#(banks, rows, accWidth) readResponse;
    method Action consumeRead;

    method Bool writeReady;
    method Action write(
        AccumulatorBank#(banks) bank,
        AccumulatorRow#(rows) row,
        Bool accumulate,
        Int#(accWidth) value
    );
    method Bool writeCompleteValid;
    method AccumulatorWriteCompletion#(banks, rows) writeComplete;
    method Action consumeWriteComplete;
endinterface

module mkAccumulatorMem(AccumulatorMemIfc#(banks, rows, accWidth));
    Vector#(
        banks,
        RegFile#(AccumulatorRow#(rows), Int#(accWidth))
    ) memories <- replicateM(mkRegFileFull);
    FIFOF#(
        AccumulatorReadReq#(banks, rows)
    ) readRequests <- mkPipelineFIFOF;
    FIFOF#(
        AccumulatorReadResponse#(banks, rows, accWidth)
    ) readResponses <- mkPipelineFIFOF;
    FIFOF#(
        AccumulatorWriteCompletion#(banks, rows)
    ) writeCompletions <- mkPipelineFIFOF;
    Reg#(
        Maybe#(AccumulatorPendingWrite#(banks, rows, accWidth))
    ) pendingAccumulate <- mkReg(tagged Invalid);
    // Global write priority is the first functional policy. Split into
    // per-bank arbiters when overlap throughput becomes required.
    PulseWire writeAccepted <- mkPulseWire;

    rule serveRead (
        readRequests.notEmpty
        && readResponses.notFull
        && !writeAccepted
    );
        let request = readRequests.first;
        readRequests.deq;
        Int#(accWidth) value = 0;
        for (Integer bankIndex = 0; bankIndex < valueOf(banks); bankIndex = bankIndex + 1) begin
            if (request.bank == fromInteger(bankIndex)) begin
                value = memories[bankIndex].sub(request.row);
            end
        end
        readResponses.enq(AccumulatorReadResponse {
            bank: request.bank,
            row: request.row,
            value: value
        });
    endrule

    rule commitAccumulate (
        isValid(pendingAccumulate)
        && writeCompletions.notFull
    );
        let pending = fromMaybe(?, pendingAccumulate);
        for (Integer bankIndex = 0; bankIndex < valueOf(banks); bankIndex = bankIndex + 1) begin
            if (pending.bank == fromInteger(bankIndex)) begin
                memories[bankIndex].upd(pending.row, pending.value);
            end
        end
        writeCompletions.enq(AccumulatorWriteCompletion {
            bank: pending.bank,
            row: pending.row
        });
        pendingAccumulate <= tagged Invalid;
        writeAccepted.send;
    endrule

    method Bool readReady = readRequests.notFull && !writeAccepted;

    method Action requestRead(
        AccumulatorBank#(banks) bank,
        AccumulatorRow#(rows) row
    ) if (readRequests.notFull && !writeAccepted);
        Bool valid =
            bank < fromInteger(valueOf(banks))
            && row < fromInteger(valueOf(rows));
        dynamicAssert(bank < fromInteger(valueOf(banks)), "accumulator read bank out of range");
        dynamicAssert(row < fromInteger(valueOf(rows)), "accumulator read row out of range");
        if (valid) begin
            readRequests.enq(AccumulatorReadReq { bank: bank, row: row });
        end
    endmethod

    method Bool readValid = readResponses.notEmpty;

    method AccumulatorReadResponse#(banks, rows, accWidth) readResponse
        if (readResponses.notEmpty);
        return readResponses.first;
    endmethod

    method Action consumeRead if (readResponses.notEmpty);
        readResponses.deq;
    endmethod

    method Bool writeReady =
        !isValid(pendingAccumulate)
        && writeCompletions.notFull;

    method Action write(
        AccumulatorBank#(banks) bank,
        AccumulatorRow#(rows) row,
        Bool accumulate,
        Int#(accWidth) value
    ) if (!isValid(pendingAccumulate) && writeCompletions.notFull);
        Bool addressValid =
            bank < fromInteger(valueOf(banks))
            && row < fromInteger(valueOf(rows));
        Bool accepted = False;
        dynamicAssert(bank < fromInteger(valueOf(banks)), "accumulator write bank out of range");
        dynamicAssert(row < fromInteger(valueOf(rows)), "accumulator write row out of range");
        for (Integer bankIndex = 0; bankIndex < valueOf(banks); bankIndex = bankIndex + 1) begin
            if (addressValid && bank == fromInteger(bankIndex)) begin
                if (accumulate) begin
                    Int#(TAdd#(accWidth, 1)) wide =
                        signExtend(memories[bankIndex].sub(row))
                        + signExtend(value);
                    Int#(accWidth) narrowed = truncate(wide);
                    Bool fits = signExtend(narrowed) == wide;
                    dynamicAssert(
                        fits,
                        "accumulator addition overflow"
                    );
                    if (fits) begin
                        pendingAccumulate <= tagged Valid AccumulatorPendingWrite {
                            bank: bank,
                            row: row,
                            value: narrowed
                        };
                        accepted = True;
                    end
                end
                else begin
                    memories[bankIndex].upd(row, value);
                    accepted = True;
                end
            end
        end
        if (accepted && !accumulate) begin
            writeCompletions.enq(AccumulatorWriteCompletion {
                bank: bank,
                row: row
            });
        end
        if (accepted) begin
            writeAccepted.send;
        end
    endmethod

    method Bool writeCompleteValid = writeCompletions.notEmpty;

    method AccumulatorWriteCompletion#(banks, rows) writeComplete
        if (writeCompletions.notEmpty);
        return writeCompletions.first;
    endmethod

    method Action consumeWriteComplete if (writeCompletions.notEmpty);
        writeCompletions.deq;
    endmethod
endmodule

endpackage
