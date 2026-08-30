package ScratchpadBank;

import Assert::*;
import FIFOF::*;
import RegFile::*;
import SpecialFIFOs::*;
import Vector::*;

typedef Bit#(TLog#(TAdd#(rows, 1))) ScratchpadRowAddr#(numeric type rows);

interface ScratchpadBankIfc#(
    numeric type rows,
    numeric type lanes,
    type element_t
);
    method Bool readReady;
    method Action requestRead(ScratchpadRowAddr#(rows) row);

    method Bool readValid;
    method Vector#(lanes, element_t) readData;
    method Action consumeRead;

    method Bool writeReady;
    method Action write(
        ScratchpadRowAddr#(rows) row,
        Vector#(lanes, Bool) mask,
        Vector#(lanes, element_t) data
    );
endinterface

module mkScratchpadBank(ScratchpadBankIfc#(rows, lanes, element_t))
    provisos (Bits#(element_t, elementWidth));

    Vector#(
        lanes,
        RegFile#(ScratchpadRowAddr#(rows), element_t)
    ) laneMemories <- replicateM(mkRegFileFull);
    // mkPipelineFIFOF is a one-entry FIFO with concurrent deq/enq support.
    FIFOF#(ScratchpadRowAddr#(rows)) readRequests <- mkPipelineFIFOF;
    FIFOF#(Vector#(lanes, element_t)) readResponses <- mkPipelineFIFOF;
    // PulseWire guards give accepted writes priority over read issue/service.
    PulseWire writeAccepted <- mkPulseWire;

    rule serveRead (
        readRequests.notEmpty
        && readResponses.notFull
        && !writeAccepted
    );
        let row = readRequests.first;
        readRequests.deq;
        Vector#(lanes, element_t) data = replicate(?);
        for (Integer lane = 0; lane < valueOf(lanes); lane = lane + 1) begin
            data[lane] = laneMemories[lane].sub(row);
        end
        readResponses.enq(data);
    endrule

    method Bool readReady = readRequests.notFull && !writeAccepted;

    method Action requestRead(ScratchpadRowAddr#(rows) row)
        if (readRequests.notFull && !writeAccepted);
        dynamicAssert(row < fromInteger(valueOf(rows)), "scratchpad read row out of range");
        readRequests.enq(row);
    endmethod

    method Bool readValid = readResponses.notEmpty;

    method Vector#(lanes, element_t) readData if (readResponses.notEmpty);
        return readResponses.first;
    endmethod

    method Action consumeRead if (readResponses.notEmpty);
        readResponses.deq;
    endmethod

    method Bool writeReady = True;

    method Action write(
        ScratchpadRowAddr#(rows) row,
        Vector#(lanes, Bool) mask,
        Vector#(lanes, element_t) data
    );
        dynamicAssert(row < fromInteger(valueOf(rows)), "scratchpad write row out of range");
        for (Integer lane = 0; lane < valueOf(lanes); lane = lane + 1) begin
            if (mask[lane]) begin
                laneMemories[lane].upd(row, data[lane]);
            end
        end
        writeAccepted.send;
    endmethod
endmodule

endpackage
