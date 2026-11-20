// Independent reference for all 2^32 inputs of the optimized linear map.
// Yosys SAT proves mismatch=0; the two functions share no intermediate RTL.
module aes_mix_miter (
    input wire [31:0] column,
    output wire mismatch
);
    `include "mdm_aes_mix_balanced.vh"

    function automatic [7:0] ref_xtime(input [7:0] b);
        ref_xtime = {b[6:0],1'b0} ^ (b[7] ? 8'h1b : 8'h00);
    endfunction

    wire [7:0] a = column[31:24];
    wire [7:0] b = column[23:16];
    wire [7:0] c = column[15:8];
    wire [7:0] d = column[7:0];
    wire [31:0] reference = {
        ref_xtime(a) ^ ref_xtime(b) ^ b ^ c ^ d,
        a ^ ref_xtime(b) ^ ref_xtime(c) ^ c ^ d,
        a ^ b ^ ref_xtime(c) ^ ref_xtime(d) ^ d,
        ref_xtime(a) ^ a ^ b ^ c ^ ref_xtime(d)
    };
    assign mismatch = aes_mix_column_balanced(column) != reference;
endmodule
