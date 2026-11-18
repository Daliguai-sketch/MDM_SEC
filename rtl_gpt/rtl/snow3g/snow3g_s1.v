module snow3g_s1 (
    input  wire [31:0] i_data,
    output wire [31:0] o_data
);

wire [7:0] s0;
wire [7:0] s1;
wire [7:0] s2;
wire [7:0] s3;

snow3g_sbox_sr u_sr0 (
    .i_data(i_data[31:24]),
    .o_data(s0)
);

snow3g_sbox_sr u_sr1 (
    .i_data(i_data[23:16]),
    .o_data(s1)
);

snow3g_sbox_sr u_sr2 (
    .i_data(i_data[15:8]),
    .o_data(s2)
);

snow3g_sbox_sr u_sr3 (
    .i_data(i_data[7:0]),
    .o_data(s3)
);

function [7:0] mulx;
    input [7:0] x;
    input [7:0] c;
    begin
        mulx = {x[6:0],1'b0}
             ^ (x[7] ? c : 8'h00);
    end
endfunction

wire [7:0] m0;
wire [7:0] m1;
wire [7:0] m2;
wire [7:0] m3;

assign m0 = mulx(s0,8'h1B);
assign m1 = mulx(s1,8'h1B);
assign m2 = mulx(s2,8'h1B);
assign m3 = mulx(s3,8'h1B);

wire [7:0] r0;
wire [7:0] r1;
wire [7:0] r2;
wire [7:0] r3;

//assign r0 = m0 ^ m1 ^ s1 ^ s2 ^ m3 ^ s3;
assign r0 = m0 ^ s1 ^ s2 ^ m3 ^ s3;
assign r1 = m0 ^ s0 ^ m1 ^ s2 ^ s3;
assign r2 = s0 ^ m1 ^ s1 ^ m2 ^ s3;
assign r3 = s0 ^ s1 ^ m2 ^ s2 ^ m3;

assign o_data = {r0,r1,r2,r3};

endmodule