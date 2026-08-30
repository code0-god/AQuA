package AquaMath;

function UInt#(width) min3(
    UInt#(width) first,
    UInt#(width) second,
    UInt#(width) third
);
    return min(first, min(second, third));
endfunction

endpackage
