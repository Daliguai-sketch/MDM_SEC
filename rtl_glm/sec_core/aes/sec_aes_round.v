//============================================================================
// Module : sec_aes_round
// Desc   : Combinational AES round function.
//          Implements SubBytes + ShiftRows + MixColumns + AddRoundKey.
//          Converted from Python sub_bytes/shift_rows/mix_columns/
//          add_round_key in sec_aes_core_enc.py.
//
// State layout (128-bit, column-major, matches Python state[word][byte]):
//   state[127:96] = col0 = {row0, row1, row2, row3} of msg[0]
//   state[95:64]  = col1 = ... of msg[1]
//   state[63:32]  = col2 = ... of msg[2]
//   state[31:0]   = col3 = ... of msg[3]
//   Each 32-bit word: [31:24]=row0(MSB), [23:16]=row1, [15:8]=row2, [7:0]=row3
//============================================================================
module sec_aes_round (
    input  wire [127:0] i_state,
    input  wire [127:0] i_rk,
    input  wire         i_last,      // 1: final round (no MixColumns)
    output wire [127:0] o_state
);

    // ---- Extract state bytes s[row][col] ----
    wire [7:0] s00, s10, s20, s30;  // column 0
    wire [7:0] s01, s11, s21, s31;  // column 1
    wire [7:0] s02, s12, s22, s32;  // column 2
    wire [7:0] s03, s13, s23, s33;  // column 3

    assign {s00, s10, s20, s30} = i_state[127:96];
    assign {s01, s11, s21, s31} = i_state[95:64];
    assign {s02, s12, s22, s32} = i_state[63:32];
    assign {s03, s13, s23, s33} = i_state[31:0];

    // ---- SubBytes: 16 S-box lookups ----
    wire [7:0] b00, b10, b20, b30;
    wire [7:0] b01, b11, b21, b31;
    wire [7:0] b02, b12, b22, b32;
    wire [7:0] b03, b13, b23, b33;

    sec_aes_sbox u_sb00 (.i_addr(s00), .o_dout(b00));
    sec_aes_sbox u_sb10 (.i_addr(s10), .o_dout(b10));
    sec_aes_sbox u_sb20 (.i_addr(s20), .o_dout(b20));
    sec_aes_sbox u_sb30 (.i_addr(s30), .o_dout(b30));
    sec_aes_sbox u_sb01 (.i_addr(s01), .o_dout(b01));
    sec_aes_sbox u_sb11 (.i_addr(s11), .o_dout(b11));
    sec_aes_sbox u_sb21 (.i_addr(s21), .o_dout(b21));
    sec_aes_sbox u_sb31 (.i_addr(s31), .o_dout(b31));
    sec_aes_sbox u_sb02 (.i_addr(s02), .o_dout(b02));
    sec_aes_sbox u_sb12 (.i_addr(s12), .o_dout(b12));
    sec_aes_sbox u_sb22 (.i_addr(s22), .o_dout(b22));
    sec_aes_sbox u_sb32 (.i_addr(s32), .o_dout(b32));
    sec_aes_sbox u_sb03 (.i_addr(s03), .o_dout(b03));
    sec_aes_sbox u_sb13 (.i_addr(s13), .o_dout(b13));
    sec_aes_sbox u_sb23 (.i_addr(s23), .o_dout(b23));
    sec_aes_sbox u_sb33 (.i_addr(s33), .o_dout(b33));

    // ---- ShiftRows (row r shifted left by r) ----
    // Row 0: no shift
    // Row 1: [b10,b11,b12,b13] -> [b11,b12,b13,b10]
    // Row 2: [b20,b21,b22,b23] -> [b22,b23,b20,b21]
    // Row 3: [b30,b31,b32,b33] -> [b33,b30,b31,b32]
    wire [7:0] r00, r10, r20, r30;
    wire [7:0] r01, r11, r21, r31;
    wire [7:0] r02, r12, r22, r32;
    wire [7:0] r03, r13, r23, r33;

    assign r00=b00; assign r01=b01; assign r02=b02; assign r03=b03;           // row 0
    assign r10=b11; assign r11=b12; assign r12=b13; assign r13=b10;           // row 1
    assign r20=b22; assign r21=b23; assign r22=b20; assign r23=b21;           // row 2
    assign r30=b33; assign r31=b30; assign r32=b31; assign r33=b32;           // row 3

    // ---- MixColumns (per column) ----
    // xtime(x) = (x<<1) ^ (x[7] ? 8'h1B : 8'h00)
    // 2*x = xtime(x),  3*x = xtime(x) ^ x
    function [7:0] xtime;
        input [7:0] x;
        begin
            xtime = (x[7]) ? ((x << 1) ^ 8'h1B) : (x << 1);
        end
    endfunction

    // Column 0
    wire [7:0] m00, m10, m20, m30;
    assign m00 = xtime(r00) ^ xtime(r10) ^ r10 ^ r20 ^ r30;  // 2*r0 ^ 3*r1 ^ r2 ^ r3
    assign m10 = r00 ^ xtime(r10) ^ xtime(r20) ^ r20 ^ r30;  // r0 ^ 2*r1 ^ 3*r2 ^ r3
    assign m20 = r00 ^ r10 ^ xtime(r20) ^ xtime(r30) ^ r30;  // r0 ^ r1 ^ 2*r2 ^ 3*r3
    assign m30 = xtime(r00) ^ r00 ^ r10 ^ r20 ^ xtime(r30);  // 3*r0 ^ r1 ^ r2 ^ 2*r3

    // Column 1
    wire [7:0] m01, m11, m21, m31;
    assign m01 = xtime(r01) ^ xtime(r11) ^ r11 ^ r21 ^ r31;
    assign m11 = r01 ^ xtime(r11) ^ xtime(r21) ^ r21 ^ r31;
    assign m21 = r01 ^ r11 ^ xtime(r21) ^ xtime(r31) ^ r31;
    assign m31 = xtime(r01) ^ r01 ^ r11 ^ r21 ^ xtime(r31);

    // Column 2
    wire [7:0] m02, m12, m22, m32;
    assign m02 = xtime(r02) ^ xtime(r12) ^ r12 ^ r22 ^ r32;
    assign m12 = r02 ^ xtime(r12) ^ xtime(r22) ^ r22 ^ r32;
    assign m22 = r02 ^ r12 ^ xtime(r22) ^ xtime(r32) ^ r32;
    assign m32 = xtime(r02) ^ r02 ^ r12 ^ r22 ^ xtime(r32);

    // Column 3
    wire [7:0] m03, m13, m23, m33;
    assign m03 = xtime(r03) ^ xtime(r13) ^ r13 ^ r23 ^ r33;
    assign m13 = r03 ^ xtime(r13) ^ xtime(r23) ^ r23 ^ r33;
    assign m23 = r03 ^ r13 ^ xtime(r23) ^ xtime(r33) ^ r33;
    assign m33 = xtime(r03) ^ r03 ^ r13 ^ r23 ^ xtime(r33);

    // ---- Select MixColumns or bypass (last round) ----
    wire [7:0] c00, c10, c20, c30;
    wire [7:0] c01, c11, c21, c31;
    wire [7:0] c02, c12, c22, c32;
    wire [7:0] c03, c13, c23, c33;

    assign c00 = i_last ? r00 : m00;
    assign c10 = i_last ? r10 : m10;
    assign c20 = i_last ? r20 : m20;
    assign c30 = i_last ? r30 : m30;
    assign c01 = i_last ? r01 : m01;
    assign c11 = i_last ? r11 : m11;
    assign c21 = i_last ? r21 : m21;
    assign c31 = i_last ? r31 : m31;
    assign c02 = i_last ? r02 : m02;
    assign c12 = i_last ? r12 : m12;
    assign c22 = i_last ? r22 : m22;
    assign c32 = i_last ? r32 : m32;
    assign c03 = i_last ? r03 : m03;
    assign c13 = i_last ? r13 : m13;
    assign c23 = i_last ? r23 : m23;
    assign c33 = i_last ? r33 : m33;

    // ---- AddRoundKey ----
    wire [127:0] after_mc;
    assign after_mc = {{c00,c10,c20,c30}, {c01,c11,c21,c31},
                       {c02,c12,c22,c32}, {c03,c13,c23,c33}};
    assign o_state = after_mc ^ i_rk;

endmodule
