/*
 * Copyright (c) 2016 Thomas Pornin <pornin@bolet.org>
 *
 * Permission is hereby granted, free of charge, to any person obtaining
 * a copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, sublicense, and/or sell copies of the Software, and to
 * permit persons to whom the Software is furnished to do so, subject to
 * the following conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS
 * BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN
 * ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
 * CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// Adapted from BearSSL src/symcipher/aes_ct64.c (MIT), revision
// 6a1dab03beac9a324fdaed36ffdeb5081ac64b9a. The Boyar-Peralta
// circuit is split into independently reportable synthesis hierarchies.

module mdm_aes_sbox_linear_top (
    input wire [7:0] value,
    output wire [21:1] y
);
    wire x0, x1, x2, x3, x4, x5, x6, x7;
    wire t0, t1;
    wire y1, y2, y3, y4, y5, y6, y7, y8, y9;
    wire y10, y11, y12, y13, y14, y15, y16, y17, y18;
    wire y19, y20, y21;
    assign x0 = value[7];
    assign x1 = value[6];
    assign x2 = value[5];
    assign x3 = value[4];
    assign x4 = value[3];
    assign x5 = value[2];
    assign x6 = value[1];
    assign x7 = value[0];
    assign y14 = x3 ^ x5;
    assign y13 = x0 ^ x6;
    assign y9 = x0 ^ x3;
    assign y8 = x0 ^ x5;
    assign t0 = x1 ^ x2;
    assign y1 = t0 ^ x7;
    assign y4 = y1 ^ x3;
    assign y12 = y13 ^ y14;
    assign y2 = y1 ^ x0;
    assign y5 = y1 ^ x6;
    assign y3 = y5 ^ y8;
    assign t1 = x4 ^ y12;
    assign y15 = t1 ^ x5;
    assign y20 = t1 ^ x1;
    assign y6 = y15 ^ x7;
    assign y10 = y15 ^ t0;
    assign y11 = y20 ^ y9;
    assign y7 = x7 ^ y11;
    assign y17 = y10 ^ y11;
    assign y19 = y10 ^ y8;
    assign y16 = t0 ^ y11;
    assign y21 = y13 ^ y16;
    assign y18 = x0 ^ y16;
    assign y = {y21,y20,y19,y18,y17,y16,y15,y14,y13,y12,y11,y10,y9,y8,y7,y6,y5,y4,y3,y2,y1};
endmodule

module mdm_aes_sbox_nonlinear (
    input wire [21:1] y,
    input wire x7,
    output wire [17:0] z
);
    wire t2, t3, t4, t5, t6, t7, t8, t9, t10, t11;
    wire t12, t13, t14, t15, t16, t17, t18, t19, t20, t21;
    wire t22, t23, t24, t25, t26, t27, t28, t29, t30, t31;
    wire t32, t33, t34, t35, t36, t37, t38, t39, t40, t41;
    wire t42, t43, t44, t45;
    assign t2 = y[12] & y[15];
    assign t3 = y[3] & y[6];
    assign t4 = t3 ^ t2;
    assign t5 = y[4] & x7;
    assign t6 = t5 ^ t2;
    assign t7 = y[13] & y[16];
    assign t8 = y[5] & y[1];
    assign t9 = t8 ^ t7;
    assign t10 = y[2] & y[7];
    assign t11 = t10 ^ t7;
    assign t12 = y[9] & y[11];
    assign t13 = y[14] & y[17];
    assign t14 = t13 ^ t12;
    assign t15 = y[8] & y[10];
    assign t16 = t15 ^ t12;
    assign t17 = t4 ^ t14;
    assign t18 = t6 ^ t16;
    assign t19 = t9 ^ t14;
    assign t20 = t11 ^ t16;
    assign t21 = t17 ^ y[20];
    assign t22 = t18 ^ y[19];
    assign t23 = t19 ^ y[21];
    assign t24 = t20 ^ y[18];
    assign t25 = t21 ^ t22;
    assign t26 = t21 & t23;
    assign t27 = t24 ^ t26;
    assign t28 = t25 & t27;
    assign t29 = t28 ^ t22;
    assign t30 = t23 ^ t24;
    assign t31 = t22 ^ t26;
    assign t32 = t31 & t30;
    assign t33 = t32 ^ t24;
    assign t34 = t23 ^ t33;
    assign t35 = t27 ^ t33;
    assign t36 = t24 & t35;
    assign t37 = t36 ^ t34;
    assign t38 = t27 ^ t36;
    assign t39 = t29 & t38;
    assign t40 = t25 ^ t39;
    assign t41 = t40 ^ t37;
    assign t42 = t29 ^ t33;
    assign t43 = t29 ^ t40;
    assign t44 = t33 ^ t37;
    assign t45 = t42 ^ t41;
    assign z[0] = t44 & y[15];
    assign z[1] = t37 & y[6];
    assign z[2] = t33 & x7;
    assign z[3] = t43 & y[16];
    assign z[4] = t40 & y[1];
    assign z[5] = t29 & y[7];
    assign z[6] = t42 & y[11];
    assign z[7] = t45 & y[17];
    assign z[8] = t41 & y[10];
    assign z[9] = t44 & y[12];
    assign z[10] = t37 & y[3];
    assign z[11] = t33 & y[4];
    assign z[12] = t43 & y[13];
    assign z[13] = t40 & y[5];
    assign z[14] = t29 & y[2];
    assign z[15] = t42 & y[9];
    assign z[16] = t45 & y[14];
    assign z[17] = t41 & y[8];
endmodule

module mdm_aes_sbox_linear_bottom (
    input wire [17:0] z,
    output wire [7:0] result
);
    wire t46, t47, t48, t49, t50, t51, t52, t53, t54, t55;
    wire t56, t57, t58, t59, t60, t61, t62, t63, t64, t65;
    wire t66, t67;
    wire s0, s1, s2, s3, s4, s5, s6, s7;
    assign t46 = z[15] ^ z[16];
    assign t47 = z[10] ^ z[11];
    assign t48 = z[5] ^ z[13];
    assign t49 = z[9] ^ z[10];
    assign t50 = z[2] ^ z[12];
    assign t51 = z[2] ^ z[5];
    assign t52 = z[7] ^ z[8];
    assign t53 = z[0] ^ z[3];
    assign t54 = z[6] ^ z[7];
    assign t55 = z[16] ^ z[17];
    assign t56 = z[12] ^ t48;
    assign t57 = t50 ^ t53;
    assign t58 = z[4] ^ t46;
    assign t59 = z[3] ^ t54;
    assign t60 = t46 ^ t57;
    assign t61 = z[14] ^ t57;
    assign t62 = t52 ^ t58;
    assign t63 = t49 ^ t58;
    assign t64 = z[4] ^ t59;
    assign t65 = t61 ^ t62;
    assign t66 = z[1] ^ t63;
    assign s0 = t59 ^ t63;
    assign s6 = t56 ^ ~t62;
    assign s7 = t48 ^ ~t60;
    assign t67 = t64 ^ t65;
    assign s3 = t53 ^ t66;
    assign s4 = t51 ^ t66;
    assign s5 = t47 ^ t65;
    assign s1 = t64 ^ ~s3;
    assign s2 = t55 ^ ~t67;
    assign result = {s0,s1,s2,s3,s4,s5,s6,s7};
endmodule

module mdm_aes_sbox (
    input wire [7:0] value,
    output wire [7:0] result
);
    wire [21:1] y;
    wire [17:0] z;
    mdm_aes_sbox_linear_top u_top (.value(value), .y(y));
    mdm_aes_sbox_nonlinear u_nonlinear (.y(y), .x7(value[0]), .z(z));
    mdm_aes_sbox_linear_bottom u_bottom (.z(z), .result(result));
endmodule
