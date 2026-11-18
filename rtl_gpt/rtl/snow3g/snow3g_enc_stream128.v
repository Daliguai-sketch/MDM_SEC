module snow3g_enc_stream128 (
    input  wire         clk,
    input  wire         rst_n,

    // Transaction start
    input  wire         i_start,
    output wire         o_start_ready,

    input  wire [127:0] i_key,
    input  wire [127:0] i_iv,

    // Number of 128-bit keystream blocks
    input  wire [15:0]  i_block_num,

    // 128-bit keystream output
    output wire [127:0] o_stream,
    output wire         o_stream_vld,
    input  wire         i_stream_ready,

    // Transaction status
    output wire         o_busy,
    output reg          o_done
);

    localparam ST_IDLE       = 3'd0;
    localparam ST_CLEAR      = 3'd1;
    localparam ST_INIT       = 3'd2;
    localparam ST_WAIT_INIT  = 3'd3;
    localparam ST_REQ_START  = 3'd4;
    localparam ST_RUN        = 3'd5;

    reg [2:0] state;

    reg [127:0] key_reg;
    reg [127:0] iv_reg;

    reg [15:0] block_num_reg;
    reg [15:0] output_count;

    wire snow_start_ready;
    wire snow_ready;
    wire snow_busy;

    reg  snow_start;

    wire snow_req;
    wire snow_req_ready;

    wire [31:0] snow_word;
    wire        snow_word_vld;
    wire        snow_word_ready;

    reg packer_clear;

    reg req_start;

    wire req_start_ready;
    wire req_busy;
    wire req_done;

    wire [127:0] packed_stream;
    wire         packed_stream_vld;
    wire packed_stream_ready;

    wire output_fire;

    wire start_fire;

    assign o_start_ready =
        (state == ST_IDLE);

    assign start_fire =
        i_start && o_start_ready;

    assign o_busy =
        (state != ST_IDLE);

    assign o_stream =
        packed_stream;

    assign packed_stream_ready =
        i_stream_ready &&
        (state == ST_RUN);

    assign o_stream_vld =
        packed_stream_vld &&
        (state == ST_RUN);

    assign output_fire =
        o_stream_vld &&
        i_stream_ready;


    /*
     * SNOW3G ENC Core
     */

    snow3g_enc u_snow3g_enc (
        .clk                (clk),
        .rst_n              (rst_n),

        .i_start            (snow_start),
        .o_start_ready      (snow_start_ready),

        .i_key              (key_reg),
        .i_iv               (iv_reg),

        .o_ready            (snow_ready),

        .i_stream_req       (snow_req),
        .o_stream_req_ready (snow_req_ready),

        .o_stream           (snow_word),
        .o_stream_vld       (snow_word_vld),
        .i_stream_ready     (snow_word_ready),

        .o_busy             (snow_busy)
    );


    /*
     * Word request controller
     */

    sec_stream_word_req_ctrl u_req_ctrl (
        .clk              (clk),
        .rst_n            (rst_n),

        .i_start          (req_start),
        .o_start_ready    (req_start_ready),

        .i_block_num      (block_num_reg),

        .o_word_req       (snow_req),
        .i_word_req_ready (snow_req_ready),

        .o_busy           (req_busy),
        .o_done           (req_done)
    );


    /*
     * 32-to-128 Packer
     *
     * Temporary integration instance.
     *
     * Final SEC ENC TOP will share one Packer
     * between SNOW3G and ZUC.
     */

    sec_stream_packer_32to128 u_packer (
        .clk            (clk),
        .rst_n          (rst_n),

        .i_clear        (packer_clear),

        .i_word         (snow_word),
        .i_word_vld     (snow_word_vld),
        .o_word_ready   (snow_word_ready),

        .o_stream       (packed_stream),
        .o_stream_vld   (packed_stream_vld),
        .i_stream_ready (packed_stream_ready)
    );


    /*
     * Control FSM
     */

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= ST_IDLE;

            key_reg <= 128'b0;
            iv_reg  <= 128'b0;

            block_num_reg <= 16'd0;
            output_count  <= 16'd0;

            snow_start <= 1'b0;
            packer_clear <= 1'b0;
            req_start <= 1'b0;

            o_done <= 1'b0;

        end
        else begin

            snow_start  <= 1'b0;
            packer_clear <= 1'b0;
            req_start   <= 1'b0;

            o_done <= 1'b0;

            case (state)

                ST_IDLE: begin

                    if (start_fire) begin

                        key_reg <= i_key;
                        iv_reg  <= i_iv;

                        block_num_reg <= i_block_num;

                        output_count <= 16'd0;

                        state <= ST_CLEAR;

                    end

                end


                ST_CLEAR: begin

                    packer_clear <= 1'b1;

                    state <= ST_INIT;

                end


                ST_INIT: begin

                    /*
                     * Wait until Core accepts
                     * initialization.
                     */

                    if (snow_start_ready) begin

                        snow_start <= 1'b1;

                        state <= ST_WAIT_INIT;

                    end

                end


                ST_WAIT_INIT: begin

                    if (snow_ready) begin

                        if (block_num_reg == 16'd0) begin

                            o_done <= 1'b1;

                            state <= ST_IDLE;

                        end
                        else begin

                            state <= ST_REQ_START;

                        end

                    end

                end


                ST_REQ_START: begin

                    if (req_start_ready) begin

                        req_start <= 1'b1;

                        state <= ST_RUN;

                    end

                end


                ST_RUN: begin

                    if (output_fire) begin

                        output_count <= output_count + 16'd1;

                        if (output_count ==
                            block_num_reg - 16'd1) begin

                            o_done <= 1'b1;

                            state <= ST_IDLE;

                        end

                    end

                end


                default: begin

                    state <= ST_IDLE;

                end

            endcase

        end

    end

endmodule