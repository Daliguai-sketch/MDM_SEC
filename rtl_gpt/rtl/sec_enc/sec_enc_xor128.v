module sec_enc_xor128 (
    input  wire         clk,
    input  wire         rst_n,

    // Data input
    input  wire [127:0] i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,

    input  wire         i_data_last,
    input  wire [4:0]   i_valid_bytes,

    // Keystream input
    input  wire [127:0] i_stream,
    input  wire         i_stream_vld,
    output wire         o_stream_ready,

    // Cipher output
    output wire [127:0] o_data,
    output wire         o_data_vld,
    input  wire         i_data_ready,

    output wire         o_data_last,
    output wire [4:0]   o_valid_bytes
);

    reg [127:0] data_reg;
    reg         valid_reg;
    reg         last_reg;
    reg [4:0]   valid_bytes_reg;

    wire stage_ready;
    wire input_fire;

    wire [127:0] xor_data;


    /*
     * Output register can accept new data when:
     *
     * 1. Empty
     * 2. Previous output consumed
     */

    assign stage_ready =
        !valid_reg ||
        i_data_ready;


    /*
     * Both data and keystream must be valid.
     */

    assign o_data_ready =
        stage_ready &&
        i_stream_vld;

    assign o_stream_ready =
        stage_ready &&
        i_data_vld;


    assign input_fire =
        i_data_vld &&
        i_stream_vld &&
        stage_ready;


    /*
     * Unified XOR
     */

    assign xor_data =
        i_data ^ i_stream;


    /*
     * Output
     */

    assign o_data =
        data_reg;

    assign o_data_vld =
        valid_reg;

    assign o_data_last =
        last_reg;

    assign o_valid_bytes =
        valid_bytes_reg;


    /*
     * Registered output
     */

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            data_reg <= 128'b0;

            valid_reg <= 1'b0;

            last_reg <= 1'b0;

            valid_bytes_reg <= 5'd0;

        end
        else begin

            if (stage_ready) begin

                if (input_fire) begin

                    data_reg <= xor_data;

                    valid_reg <= 1'b1;

                    last_reg <= i_data_last;

                    valid_bytes_reg <=
                        i_valid_bytes;

                end
                else begin

                    valid_reg <= 1'b0;

                end

            end

        end

    end

endmodule