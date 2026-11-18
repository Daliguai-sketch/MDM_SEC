module snow3g_s2 (
    input  wire [31:0] i_data,
    output wire [31:0] o_data
);

wire [7:0] q0;
wire [7:0] q1;
wire [7:0] q2;
wire [7:0] q3;

snow3g_sbox_sq u_sq0 (
    .i_data(i_data[31:24]),
    .o_data(q0)
);

snow3g_sbox_sq u_sq1 (
    .i_data(i_data[23:16]),
    .o_data(q1)
);

snow3g_sbox_sq u_sq2 (
    .i_data(i_data[15:8]),
    .o_data(q2)
);

snow3g_sbox_sq u_sq3 (
    .i_data(i_data[7:0]),
    .o_data(q3)
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

assign m0 = mulx(q0,8'h69);
assign m1 = mulx(q1,8'h69);
assign m2 = mulx(q2,8'h69);
assign m3 = mulx(q3,8'h69);

wire [7:0] r0;
wire [7:0] r1;
wire [7:0] r2;
wire [7:0] r3;

assign r0 = m0 ^ q1 ^ q2 ^ m3 ^ q3;
assign r1 = m0 ^ q0 ^ m1 ^ q2 ^ q3;
assign r2 = q0 ^ m1 ^ q1 ^ m2 ^ q3;
assign r3 = q0 ^ q1 ^ m2 ^ q2 ^ m3;

assign o_data = {r0,r1,r2,r3};

endmodule