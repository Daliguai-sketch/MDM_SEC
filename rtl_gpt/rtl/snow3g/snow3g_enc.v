module snow3g_enc (
    input  wire         clk,
    input  wire         rst_n,

    // Packet initialization
    input  wire         i_start,
    output wire         o_start_ready,

    input  wire [127:0] i_key,
    input  wire [127:0] i_iv,

    // Initialization completed
    output wire         o_ready,

    // 32-bit Keystream request
    input  wire         i_stream_req,
    output wire         o_stream_req_ready,

    // 32-bit Keystream output
    output wire [31:0]  o_stream,
    output wire         o_stream_vld,
    input  wire         i_stream_ready,

    output wire         o_busy
);

    snow3g_core u_snow3g_core (
        .clk                (clk),
        .rst_n              (rst_n),

        .i_init             (i_start),
        .o_init_ready       (o_start_ready),

        .i_key              (i_key),
        .i_iv               (i_iv),

        .o_core_ready       (o_ready),

        .i_stream_req       (i_stream_req),
        .o_stream_req_ready (o_stream_req_ready),

        .o_stream           (o_stream),
        .o_stream_vld       (o_stream_vld),
        .i_stream_ready     (i_stream_ready),

        .o_busy             (o_busy)
    );

endmodule