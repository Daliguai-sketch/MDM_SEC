module aes_cmac_subkey (
    input  wire [127:0] i_l,
    output wire [127:0] o_k1,
    output wire [127:0] o_k2
);

wire [127:0] k1_tmp;

assign k1_tmp =
    {i_l[126:0], 1'b0}
    ^ (i_l[127] ? 128'h87 : 128'h0);

assign o_k1 = k1_tmp;

assign o_k2 =
    {k1_tmp[126:0], 1'b0}
    ^ (k1_tmp[127] ? 128'h87 : 128'h0);

endmodule