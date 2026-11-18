//============================================================================
// Module : sec_aes_key_expansion
// Desc   : AES-128 key expansion. Generates 11 round keys (44 words = 1408 bits)
//          from a 128-bit key.
//          Converted from Python key_expansion()/aes_enc_key_exp() in
//          sec_aes_core_enc.py. Key words are reversed before expansion
//          (k = [key[3], key[2], key[1], key[0]]) as in the Python reference.
//============================================================================
module sec_aes_key_expansion (
    input  wire [127:0] i_key,
    output wire [127:0] o_rk0,  o_rk1,  o_rk2,  o_rk3,
    output wire [127:0] o_rk4,  o_rk5,  o_rk6,  o_rk7,
    output wire [127:0] o_rk8,  o_rk9,  o_rk10
);

    // ---- Round constants RCON (from Python RCON[]) ----
    wire [31:0] rcon [0:10];
    assign rcon[0]  = 32'h0000_0000;
    assign rcon[1]  = 32'h0100_0000;
    assign rcon[2]  = 32'h0200_0000;
    assign rcon[3]  = 32'h0400_0000;
    assign rcon[4]  = 32'h0800_0000;
    assign rcon[5]  = 32'h1000_0000;
    assign rcon[6]  = 32'h2000_0000;
    assign rcon[7]  = 32'h4000_0000;
    assign rcon[8]  = 32'h8000_0000;
    assign rcon[9]  = 32'h1B00_0000;
    assign rcon[10] = 32'h3600_0000;

    // ---- Expanded key words w[0..43] ----
    wire [31:0] w [0:43];

    // Step 1: reverse key words (Python: k.append(key[Nk-1-i]))
    assign w[0]  = i_key[31:0];    // key[3]
    assign w[1]  = i_key[63:32];   // key[2]
    assign w[2]  = i_key[95:64];   // key[1]
    assign w[3]  = i_key[127:96];  // key[0]

    // Helper macro: SubWord(RotWord(x)) ^ rcon  for every 4th word
    // RotWord(w) = {w[23:0], w[31:24]}
    // SubWord(w) = {SBOX[w[31:24]], SBOX[w[23:16]], SBOX[w[15:8]], SBOX[w[7:0]]}

    // Word 4
    wire [31:0] rw4  = {w[3][23:0], w[3][31:24]};
    wire [7:0] sw4_0, sw4_1, sw4_2, sw4_3;
    sec_aes_sbox u_sw4_0 (.i_addr(rw4[31:24]), .o_dout(sw4_0));
    sec_aes_sbox u_sw4_1 (.i_addr(rw4[23:16]), .o_dout(sw4_1));
    sec_aes_sbox u_sw4_2 (.i_addr(rw4[15:8]),  .o_dout(sw4_2));
    sec_aes_sbox u_sw4_3 (.i_addr(rw4[7:0]),   .o_dout(sw4_3));
    assign w[4]  = w[0] ^ ({sw4_0,sw4_1,sw4_2,sw4_3} ^ rcon[1]);
    assign w[5]  = w[1] ^ w[4];
    assign w[6]  = w[2] ^ w[5];
    assign w[7]  = w[3] ^ w[6];

    // Word 8
    wire [31:0] rw8  = {w[7][23:0], w[7][31:24]};
    wire [7:0] sw8_0, sw8_1, sw8_2, sw8_3;
    sec_aes_sbox u_sw8_0 (.i_addr(rw8[31:24]), .o_dout(sw8_0));
    sec_aes_sbox u_sw8_1 (.i_addr(rw8[23:16]), .o_dout(sw8_1));
    sec_aes_sbox u_sw8_2 (.i_addr(rw8[15:8]),  .o_dout(sw8_2));
    sec_aes_sbox u_sw8_3 (.i_addr(rw8[7:0]),   .o_dout(sw8_3));
    assign w[8]  = w[4] ^ ({sw8_0,sw8_1,sw8_2,sw8_3} ^ rcon[2]);
    assign w[9]  = w[5] ^ w[8];
    assign w[10] = w[6] ^ w[9];
    assign w[11] = w[7] ^ w[10];

    // Word 12
    wire [31:0] rw12 = {w[11][23:0], w[11][31:24]};
    wire [7:0] sw12_0, sw12_1, sw12_2, sw12_3;
    sec_aes_sbox u_sw12_0 (.i_addr(rw12[31:24]), .o_dout(sw12_0));
    sec_aes_sbox u_sw12_1 (.i_addr(rw12[23:16]), .o_dout(sw12_1));
    sec_aes_sbox u_sw12_2 (.i_addr(rw12[15:8]),  .o_dout(sw12_2));
    sec_aes_sbox u_sw12_3 (.i_addr(rw12[7:0]),   .o_dout(sw12_3));
    assign w[12] = w[8]  ^ ({sw12_0,sw12_1,sw12_2,sw12_3} ^ rcon[3]);
    assign w[13] = w[9]  ^ w[12];
    assign w[14] = w[10] ^ w[13];
    assign w[15] = w[11] ^ w[14];

    // Word 16
    wire [31:0] rw16 = {w[15][23:0], w[15][31:24]};
    wire [7:0] sw16_0, sw16_1, sw16_2, sw16_3;
    sec_aes_sbox u_sw16_0 (.i_addr(rw16[31:24]), .o_dout(sw16_0));
    sec_aes_sbox u_sw16_1 (.i_addr(rw16[23:16]), .o_dout(sw16_1));
    sec_aes_sbox u_sw16_2 (.i_addr(rw16[15:8]),  .o_dout(sw16_2));
    sec_aes_sbox u_sw16_3 (.i_addr(rw16[7:0]),   .o_dout(sw16_3));
    assign w[16] = w[12] ^ ({sw16_0,sw16_1,sw16_2,sw16_3} ^ rcon[4]);
    assign w[17] = w[13] ^ w[16];
    // Word 20
    wire [31:0] rw20 = {w[19][23:0], w[19][31:24]};
    wire [7:0] sw20_0, sw20_1, sw20_2, sw20_3;
    sec_aes_sbox u_sw20_0 (.i_addr(rw20[31:24]), .o_dout(sw20_0));
    sec_aes_sbox u_sw20_1 (.i_addr(rw20[23:16]), .o_dout(sw20_1));
    sec_aes_sbox u_sw20_2 (.i_addr(rw20[15:8]),  .o_dout(sw20_2));
    sec_aes_sbox u_sw20_3 (.i_addr(rw20[7:0]),   .o_dout(sw20_3));
    assign w[20] = w[16] ^ ({sw20_0,sw20_1,sw20_2,sw20_3} ^ rcon[5]);
    assign w[21] = w[17] ^ w[20];
    assign w[22] = w[18] ^ w[21];
    assign w[23] = w[19] ^ w[22];

    // Word 24
    wire [31:0] rw24 = {w[23][23:0], w[23][31:24]};
    wire [7:0] sw24_0, sw24_1, sw24_2, sw24_3;
    sec_aes_sbox u_sw24_0 (.i_addr(rw24[31:24]), .o_dout(sw24_0));
    sec_aes_sbox u_sw24_1 (.i_addr(rw24[23:16]), .o_dout(sw24_1));
    sec_aes_sbox u_sw24_2 (.i_addr(rw24[15:8]),  .o_dout(sw24_2));
    sec_aes_sbox u_sw24_3 (.i_addr(rw24[7:0]),   .o_dout(sw24_3));
    assign w[24] = w[20] ^ ({sw24_0,sw24_1,sw24_2,sw24_3} ^ rcon[6]);
    assign w[25] = w[21] ^ w[24];
    assign w[26] = w[22] ^ w[25];
    assign w[27] = w[23] ^ w[26];

    // Word 28
    wire [31:0] rw28 = {w[27][23:0], w[27][31:24]};
    wire [7:0] sw28_0, sw28_1, sw28_2, sw28_3;
    sec_aes_sbox u_sw28_0 (.i_addr(rw28[31:24]), .o_dout(sw28_0));
    sec_aes_sbox u_sw28_1 (.i_addr(rw28[23:16]), .o_dout(sw28_1));
    sec_aes_sbox u_sw28_2 (.i_addr(rw28[15:8]),  .o_dout(sw28_2));
    sec_aes_sbox u_sw28_3 (.i_addr(rw28[7:0]),   .o_dout(sw28_3));
    assign w[28] = w[24] ^ ({sw28_0,sw28_1,sw28_2,sw28_3} ^ rcon[7]);
    assign w[29] = w[25] ^ w[28];
    assign w[30] = w[26] ^ w[29];
    assign w[31] = w[27] ^ w[30];

    // Word 32
    wire [31:0] rw32 = {w[31][23:0], w[31][31:24]};
    wire [7:0] sw32_0, sw32_1, sw32_2, sw32_3;
    sec_aes_sbox u_sw32_0 (.i_addr(rw32[31:24]), .o_dout(sw32_0));
    sec_aes_sbox u_sw32_1 (.i_addr(rw32[23:16]), .o_dout(sw32_1));
    sec_aes_sbox u_sw32_2 (.i_addr(rw32[15:8]),  .o_dout(sw32_2));
    sec_aes_sbox u_sw32_3 (.i_addr(rw32[7:0]),   .o_dout(sw32_3));
    assign w[32] = w[28] ^ ({sw32_0,sw32_1,sw32_2,sw32_3} ^ rcon[8]);
    assign w[33] = w[29] ^ w[32];
    assign w[34] = w[30] ^ w[33];
    assign w[35] = w[31] ^ w[34];

    // Word 36
    wire [31:0] rw36 = {w[35][23:0], w[35][31:24]};
    wire [7:0] sw36_0, sw36_1, sw36_2, sw36_3;
    sec_aes_sbox u_sw36_0 (.i_addr(rw36[31:24]), .o_dout(sw36_0));
    sec_aes_sbox u_sw36_1 (.i_addr(rw36[23:16]), .o_dout(sw36_1));
    sec_aes_sbox u_sw36_2 (.i_addr(rw36[15:8]),  .o_dout(sw36_2));
    sec_aes_sbox u_sw36_3 (.i_addr(rw36[7:0]),   .o_dout(sw36_3));
    assign w[36] = w[32] ^ ({sw36_0,sw36_1,sw36_2,sw36_3} ^ rcon[9]);
    assign w[37] = w[33] ^ w[36];
    assign w[38] = w[34] ^ w[37];
    assign w[39] = w[35] ^ w[38];

    // Word 40
    wire [31:0] rw40 = {w[39][23:0], w[39][31:24]};
    wire [7:0] sw40_0, sw40_1, sw40_2, sw40_3;
    sec_aes_sbox u_sw40_0 (.i_addr(rw40[31:24]), .o_dout(sw40_0));
    sec_aes_sbox u_sw40_1 (.i_addr(rw40[23:16]), .o_dout(sw40_1));
    sec_aes_sbox u_sw40_2 (.i_addr(rw40[15:8]),  .o_dout(sw40_2));
    sec_aes_sbox u_sw40_3 (.i_addr(rw40[7:0]),   .o_dout(sw40_3));
    assign w[40] = w[36] ^ ({sw40_0,sw40_1,sw40_2,sw40_3} ^ rcon[10]);
    assign w[41] = w[37] ^ w[40];
    assign w[42] = w[38] ^ w[41];
    assign w[43] = w[39] ^ w[42];

    // ---- Pack into 11 round keys (each 128-bit) ----
    assign o_rk0  = {w[0],  w[1],  w[2],  w[3]};
    assign o_rk1  = {w[4],  w[5],  w[6],  w[7]};
    assign o_rk2  = {w[8],  w[9],  w[10], w[11]};
    assign o_rk3  = {w[12], w[13], w[14], w[15]};
    assign o_rk4  = {w[16], w[17], w[18], w[19]};
    assign o_rk5  = {w[20], w[21], w[22], w[23]};
    assign o_rk6  = {w[24], w[25], w[26], w[27]};
    assign o_rk7  = {w[28], w[29], w[30], w[31]};
    assign o_rk8  = {w[32], w[33], w[34], w[35]};
    assign o_rk9  = {w[36], w[37], w[38], w[39]};
    assign o_rk10 = {w[40], w[41], w[42], w[43]};

endmodule
    assign w[18] = w[14] ^ w[17];
    assign w[19] = w[15] ^ w[18];
