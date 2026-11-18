module aes_round_comb (
    input  wire [127:0] state_in,
    input  wire [127:0] round_key,
    input  wire         last_round,

    output wire [127:0] state_out
);

// ============================================================
// SubBytes
// ============================================================

wire [127:0] sub_state;

genvar i;

generate
    for (i = 0; i < 16; i = i + 1) begin : GEN_SUB_BYTES

        aes_sbox u_sbox (
            .din  (state_in[127-i*8 -: 8]),
            .dout (sub_state[127-i*8 -: 8])
        );

    end
endgenerate


// ============================================================
// ShiftRows
// AES State is column-major
// ============================================================

wire [7:0] b [0:15];

generate
    for (i = 0; i < 16; i = i + 1) begin : GEN_BYTE
        assign b[i] = sub_state[127-i*8 -: 8];
    end
endgenerate

wire [127:0] shift_state;

assign shift_state = {

    b[0],  b[5],  b[10], b[15],

    b[4],  b[9],  b[14], b[3],

    b[8],  b[13], b[2],  b[7],

    b[12], b[1],  b[6],  b[11]

};


// ============================================================
// GF(2^8) xtime
// ============================================================

function [7:0] xtime;

    input [7:0] x;

    begin
        xtime = {x[6:0],1'b0}
              ^ (x[7] ? 8'h1b : 8'h00);
    end

endfunction


// ============================================================
// MixColumns
// ============================================================

function [31:0] mix_column;

    input [31:0] col;

    reg [7:0] s0;
    reg [7:0] s1;
    reg [7:0] s2;
    reg [7:0] s3;

    reg [7:0] r0;
    reg [7:0] r1;
    reg [7:0] r2;
    reg [7:0] r3;

    begin

        s0 = col[31:24];
        s1 = col[23:16];
        s2 = col[15:8];
        s3 = col[7:0];

        r0 = xtime(s0) ^ xtime(s1) ^ s1 ^ s2 ^ s3;

        r1 = s0 ^ xtime(s1) ^ xtime(s2) ^ s2 ^ s3;

        r2 = s0 ^ s1 ^ xtime(s2) ^ xtime(s3) ^ s3;

        r3 = xtime(s0) ^ s0 ^ s1 ^ s2 ^ xtime(s3);

        mix_column = {r0,r1,r2,r3};

    end

endfunction


// ============================================================
// MixColumns for 4 columns
// ============================================================

wire [127:0] mix_state;

assign mix_state = {

    mix_column(shift_state[127:96]),

    mix_column(shift_state[95:64]),

    mix_column(shift_state[63:32]),

    mix_column(shift_state[31:0])

};


// ============================================================
// Last Round Bypass
// ============================================================

wire [127:0] round_data;

assign round_data = last_round
                  ? shift_state
                  : mix_state;


// ============================================================
// AddRoundKey
// ============================================================

assign state_out = round_data ^ round_key;

endmodule