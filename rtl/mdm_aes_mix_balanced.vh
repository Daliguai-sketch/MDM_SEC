/*
 * MIT License
 *
 * Copyright (c) 2026 Joe Bachir
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in all
 * copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

// Adapted from Joe Bachir's 88-XOR depth-5 forward AES MixColumns circuit:
// https://github.com/Joe-b-20/aes-mixcolumns-xor-circuits
// revision 8b4feb52a8924d3eb6d72314f67a2f38b6988eb8,
// verilog/mixcolumns_88gates_depth5.v. Upstream identifies this circuit as
// derived from Jeremy Jean's published 88-XOR circuit (ePrint 2026/1481);
// Jean has priority. The module has been converted to a Verilog-2005 function
// and its byte order reversed to match this project's MSB-first column layout.
// The XOR network is unchanged. No synthesis keep/dont_touch attributes are imposed.
//
// value={a,b,c,d}, a is the first AES column byte; output is the standard
// FIPS-197 MixColumns result in that same byte order. The 88 XOR assignments
// use s[0:31] as the inputs and s[32:119] as intermediate/output nodes.
function automatic [31:0] aes_mix_column_balanced(input [31:0] v);
    reg [119:0] s;
    reg [31:0] y;
    begin
        s[31:0] = {v[7:0],v[15:8],v[23:16],v[31:24]};
        s[32] = s[13] ^ s[29];
        s[33] = s[21] ^ s[29];
        s[34] = s[22] ^ s[30];
        s[35] = s[15] ^ s[23];
        s[36] = s[9] ^ s[17];
        s[37] = s[12] ^ s[20];
        s[38] = s[12] ^ s[28];
        s[39] = s[3] ^ s[27];
        s[40] = s[3] ^ s[19];
        s[41] = s[4] ^ s[28];
        s[42] = s[9] ^ s[25];
        s[43] = s[2] ^ s[18];
        s[44] = s[5] ^ s[13];
        s[45] = s[10] ^ s[18];
        s[46] = s[1] ^ s[25];
        s[47] = s[6] ^ s[22];
        s[48] = s[6] ^ s[14];
        s[49] = s[11] ^ s[19];
        s[50] = s[7] ^ s[23];
        s[51] = s[7] ^ s[31];
        s[52] = s[8] ^ s[16];
        s[53] = s[32] ^ s[38];
        s[54] = s[32] ^ s[47];
        s[55] = s[33] ^ s[30];
        s[56] = s[34] ^ s[15];
        s[57] = s[35] ^ s[49];
        s[58] = s[35] ^ s[52];
        s[59] = s[37] ^ s[5];
        s[60] = s[39] ^ s[4];
        s[61] = s[40] ^ s[50];
        s[62] = s[40] ^ s[51];
        s[63] = s[41] ^ s[21];
        s[64] = s[42] ^ s[45];
        s[65] = s[42] ^ s[52];
        s[66] = s[43] ^ s[26];
        s[67] = s[43] ^ s[61];
        s[68] = s[44] ^ s[14];
        s[69] = s[44] ^ s[63];
        s[70] = s[45] ^ s[11];
        s[71] = s[46] ^ s[26];
        s[72] = s[47] ^ s[50];
        s[73] = s[48] ^ s[55];
        s[74] = s[48] ^ s[31];
        s[75] = s[50] ^ s[8];
        s[76] = s[50] ^ s[58];
        s[77] = s[51] ^ s[0];
        s[78] = s[51] ^ s[56];
        s[79] = s[51] ^ s[60];
        s[80] = s[52] ^ s[77];
        s[81] = s[53] ^ s[63];
        s[82] = s[53] ^ s[59];
        s[83] = s[54] ^ s[55];
        s[84] = s[54] ^ s[68];
        s[85] = s[56] ^ s[72];
        s[86] = s[57] ^ s[20];
        s[87] = s[58] ^ s[17];
        s[88] = s[59] ^ s[33];
        s[89] = s[61] ^ s[38];
        s[90] = s[64] ^ s[71];
        s[91] = s[66] ^ s[36];
        s[92] = s[66] ^ s[10];
        s[93] = s[68] ^ s[34];
        s[94] = s[70] ^ s[39];
        s[95] = s[71] ^ s[92];
        s[96] = s[72] ^ s[74];
        s[97] = s[74] ^ s[35];
        s[98] = s[75] ^ s[0];
        s[99] = s[76] ^ s[24];
        s[100] = s[77] ^ s[24];
        s[101] = s[79] ^ s[89];
        s[102] = s[79] ^ s[37];
        s[103] = s[86] ^ s[41];
        s[104] = s[86] ^ s[89];
        s[105] = s[87] ^ s[46];
        s[106] = s[91] ^ s[64];
        s[107] = s[92] ^ s[62];
        s[108] = s[94] ^ s[57];
        s[109] = s[94] ^ s[67];
        s[110] = s[98] ^ s[99];
        s[111] = s[98] ^ s[65];
        s[112] = s[100] ^ s[1];
        s[113] = s[100] ^ s[75];
        s[114] = s[107] ^ s[109];
        s[115] = s[107] ^ s[70];
        s[116] = s[109] ^ s[35];
        s[117] = s[111] ^ s[112];
        s[118] = s[111] ^ s[87];
        s[119] = s[112] ^ s[36];
        y[0] = s[99];
        y[1] = s[118];
        y[2] = s[90];
        y[3] = s[116];
        y[4] = s[104];
        y[5] = s[81];
        y[6] = s[93];
        y[7] = s[97];
        y[8] = s[110];
        y[9] = s[105];
        y[10] = s[91];
        y[11] = s[108];
        y[12] = s[103];
        y[13] = s[88];
        y[14] = s[83];
        y[15] = s[96];
        y[16] = s[113];
        y[17] = s[117];
        y[18] = s[106];
        y[19] = s[114];
        y[20] = s[101];
        y[21] = s[82];
        y[22] = s[73];
        y[23] = s[78];
        y[24] = s[80];
        y[25] = s[119];
        y[26] = s[95];
        y[27] = s[115];
        y[28] = s[102];
        y[29] = s[69];
        y[30] = s[84];
        y[31] = s[85];
        aes_mix_column_balanced = {y[7:0],y[15:8],y[23:16],y[31:24]};
    end
endfunction
