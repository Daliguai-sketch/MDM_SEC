module snow3g_gf64_step32 (
    input  wire [63:0] i_p,
    input  wire [63:0] i_v,
    input  wire [63:0] i_acc,

    output wire [63:0] o_v,
    output wire [63:0] o_acc
);

wire [63:0] v_chain   [0:32];
wire [63:0] acc_chain [0:32];

assign v_chain[0]   = i_v;
assign acc_chain[0] = i_acc;

genvar g;

generate
    for (g = 0; g < 32; g = g + 1) begin : GEN_GF64_STEP

        assign acc_chain[g+1] =
            acc_chain[g] ^
            (v_chain[g] & {64{i_p[g]}});

        assign v_chain[g+1] =
            {v_chain[g][62:0], 1'b0} ^
            (v_chain[g][63] ? 64'h000000000000001B
                            : 64'h0000000000000000);

    end
endgenerate

assign o_v   = v_chain[32];
assign o_acc = acc_chain[32];

endmodule