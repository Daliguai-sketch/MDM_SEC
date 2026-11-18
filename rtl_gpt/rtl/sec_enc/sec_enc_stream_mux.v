module sec_enc_stream_mux (
    input  wire [1:0]   i_alg_sel,

    // AES 128-bit stream
    input  wire [127:0] i_aes_stream,
    input  wire         i_aes_vld,
    output wire         o_aes_ready,

    // Shared SNOW3G/ZUC Packer output
    input  wire [127:0] i_packed_stream,
    input  wire         i_packed_vld,
    output wire         o_packed_ready,

    // Selected stream
    output reg  [127:0] o_stream,
    output reg          o_stream_vld,
    input  wire         i_stream_ready
);

    localparam ALG_AES  = 2'd0;
    localparam ALG_SNOW = 2'd1;
    localparam ALG_ZUC  = 2'd2;
    localparam ALG_NULL = 2'd3;

    always @(*) begin

        o_stream = 128'b0;
        o_stream_vld = 1'b0;

        case (i_alg_sel)

            ALG_AES: begin

                o_stream = i_aes_stream;
                o_stream_vld = i_aes_vld;

            end

            ALG_SNOW,
            ALG_ZUC: begin

                o_stream = i_packed_stream;
                o_stream_vld = i_packed_vld;

            end

            ALG_NULL: begin

                /*
                 * NULL encryption:
                 * Zero keystream.
                 */

                o_stream = 128'b0;
                o_stream_vld = 1'b1;

            end

            default: begin

                o_stream = 128'b0;
                o_stream_vld = 1'b0;

            end

        endcase

    end


    assign o_aes_ready =
        (i_alg_sel == ALG_AES) &&
        i_stream_ready;

    assign o_packed_ready =
        ((i_alg_sel == ALG_SNOW) ||
         (i_alg_sel == ALG_ZUC)) &&
        i_stream_ready;

endmodule