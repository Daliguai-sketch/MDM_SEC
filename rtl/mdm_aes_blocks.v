// Small AES datapath building blocks. Kept as modules so hierarchical area
// reports can distinguish S-boxes, MixColumns, ShiftRows and key expansion.
module mdm_aes_subbytes4 (
    input  wire [31:0] data_in,
    output wire [31:0] data_out
);
    genvar i;
    generate
        for (i=0;
             i<4;
             i=i+1) begin: g_byte
            mdm_aes_sbox u_sbox (
                .value(data_in[31-8*i -: 8]),
                .result(data_out[31-8*i -: 8])
            );
        end
    endgenerate
endmodule

module mdm_aes_shift_rows (
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);
    genvar col,row;
    generate
        for (col=0;
             col<4;
             col=col+1) begin: g_col
            for (row=0;
                 row<4;
                 row=row+1) begin: g_row
                assign state_out[127-8*(4*col+row) -: 8] =
                       state_in[127-8*(4*((col+row)%4)+row) -: 8];
            end
        end
    endgenerate
endmodule

// SubWord is supplied by the shared four S-boxes during the key phase.
module mdm_aes_key_expand (
    input  wire [127:0] key_in,
    input  wire [31:0]  subword,
    input  wire [7:0]   rcon,
    output wire [127:0] key_out
);
    wire [31:0] w0,w1,w2,w3;
    assign w0 = key_in[127:96] ^ subword ^ {rcon,24'b0};
    assign w1 = key_in[95:64] ^ w0;
    assign w2 = key_in[63:32] ^ w1;
    assign w3 = key_in[31:0] ^ w2;
    assign key_out = {w0,w1,w2,w3};
endmodule

// One 32-bit MixColumns unit is reused for all four columns and all rounds.
module mdm_aes_mix_column (
    input  wire [31:0] data_in,
    output wire [31:0] data_out
);
    wire [7:0] a,b,c,d,total;
    wire [7:0] ab,bc,cd,da;
    wire [7:0] xab,xbc,xcd,xda;
    assign {a,b,c,d} = data_in;
    assign total = a^b^c^d;
    assign ab = a^b;
    assign bc = b^c;
    assign cd = c^d;
    assign da = d^a;
    assign xab = {ab[6:0],1'b0} ^ ({8{ab[7]}} & 8'h1b);
    assign xbc = {bc[6:0],1'b0} ^ ({8{bc[7]}} & 8'h1b);
    assign xcd = {cd[6:0],1'b0} ^ ({8{cd[7]}} & 8'h1b);
    assign xda = {da[6:0],1'b0} ^ ({8{da[7]}} & 8'h1b);
    assign data_out = {a^total^xab,b^total^xbc,c^total^xcd,d^total^xda};
endmodule

module mdm_aes_add_round_key (
    input  wire [31:0] data_in,
    input  wire [31:0] round_key,
    output wire [31:0] data_out
);
    assign data_out = data_in ^ round_key;
endmodule
