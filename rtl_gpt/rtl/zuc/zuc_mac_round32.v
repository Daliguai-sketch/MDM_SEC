module zuc_mac_round32 (
    input  wire [31:0] i_msg,
    input  wire [31:0] i_z0,
    input  wire [31:0] i_z1,

    output wire [31:0] o_mac_delta
);

    wire [63:0] z_window;

    wire [31:0] level0 [0:31];
    wire [31:0] level1 [0:15];
    wire [31:0] level2 [0:7];
    wire [31:0] level3 [0:3];
    wire [31:0] level4 [0:1];

    genvar i;

    assign z_window = {i_z0, i_z1};

    generate

        for (i = 0; i < 32; i = i + 1) begin : GEN_WINDOW

            assign level0[i] =
                {32{i_msg[31-i]}} &
                z_window[63-i -: 32];

        end

        for (i = 0; i < 16; i = i + 1) begin : GEN_L1

            assign level1[i] =
                level0[2*i] ^
                level0[2*i+1];

        end

        for (i = 0; i < 8; i = i + 1) begin : GEN_L2

            assign level2[i] =
                level1[2*i] ^
                level1[2*i+1];

        end

        for (i = 0; i < 4; i = i + 1) begin : GEN_L3

            assign level3[i] =
                level2[2*i] ^
                level2[2*i+1];

        end

        for (i = 0; i < 2; i = i + 1) begin : GEN_L4

            assign level4[i] =
                level3[2*i] ^
                level3[2*i+1];

        end

    endgenerate

    assign o_mac_delta =
        level4[0] ^ level4[1];

endmodule