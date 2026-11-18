module sec_enc_top (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         i_start,
    output wire         o_start_ready,

    input  wire [1:0]   i_alg_sel,
    input  wire [127:0] i_key,

    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    input  wire [31:0]  i_packet_bytes,

    input  wire [127:0] i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,
    input  wire         i_data_last,
    input  wire [4:0]   i_valid_bytes,

    output wire [127:0] o_data,
    output wire         o_data_vld,
    input  wire         i_data_ready,

    output wire         o_data_last,
    output wire [4:0]   o_valid_bytes,

    output wire         o_busy,
    output reg          o_done
);

    // =========================================================
    // Algorithm Encoding
    // =========================================================

    localparam [1:0] ALG_AES    = 2'd0;
    localparam [1:0] ALG_SNOW3G = 2'd1;
    localparam [1:0] ALG_ZUC    = 2'd2;
    localparam [1:0] ALG_NULL   = 2'd3;

    // =========================================================
    // FSM
    // =========================================================

    localparam [3:0] ST_IDLE         = 4'd0;
    localparam [3:0] ST_CLEAR        = 4'd1;

    localparam [3:0] ST_AES_KEY_LOAD = 4'd2;
    localparam [3:0] ST_AES_WAIT_KEY = 4'd3;
    localparam [3:0] ST_AES_CTR_INIT = 4'd4;

    localparam [3:0] ST_SNOW_INIT    = 4'd5;
    localparam [3:0] ST_ZUC_INIT     = 4'd6;

    localparam [3:0] ST_WAIT_INIT    = 4'd7;
    localparam [3:0] ST_RUN          = 4'd8;

    reg [3:0] state;

    // =========================================================
    // Packet Configuration Registers
    // =========================================================

    reg [1:0]   alg_reg;
    reg [127:0] key_reg;

    reg [31:0] count_reg;
    reg [4:0]  bearer_reg;
    reg        direction_reg;

    reg [31:0] packet_bytes_reg;

    // =========================================================
    // Block and Keystream Counters
    // =========================================================

    reg [31:0] block_total;
    reg [31:0] block_in_count;
    reg [31:0] block_out_count;

    reg [31:0] aes_req_count;

    reg [33:0] word_req_count;
    reg [33:0] word_recv_count;

    wire [31:0] start_block_total;

    assign start_block_total =
        (i_packet_bytes >> 4) +
        (|i_packet_bytes[3:0]);

    wire [33:0] word_total;

    assign word_total = {block_total, 2'b00};

    // =========================================================
    // Packet Start
    // =========================================================

    assign o_start_ready = (state == ST_IDLE);
    assign o_busy        = (state != ST_IDLE);

    wire start_fire;

    assign start_fire = i_start && o_start_ready;

    // =========================================================
    // ENC IV Generator
    // =========================================================

    wire [127:0] enc_iv;

    sec_enc_iv_gen u_enc_iv_gen (
        .i_count     (count_reg),
        .i_bearer    (bearer_reg),
        .i_direction (direction_reg),
        .o_iv        (enc_iv)
    );

    // =========================================================
    // AES-CTR Interface and Handshakes
    // =========================================================

    wire        aes_key_load;
    wire        aes_key_load_ready;
    wire        aes_key_ready;

    wire        aes_ctr_init;
    wire        aes_ctr_init_ready;

    wire        aes_stream_req;
    wire        aes_stream_req_ready;

    wire [127:0] aes_stream;
    wire         aes_stream_vld;
    wire         aes_stream_ready;

    wire aes_key_load_fire;
    wire aes_ctr_init_fire;
    wire aes_req_fire;

    assign aes_key_load = (state == ST_AES_KEY_LOAD);
    assign aes_ctr_init = (state == ST_AES_CTR_INIT);

    assign aes_key_load_fire =
        aes_key_load &&
        aes_key_load_ready;

    assign aes_ctr_init_fire =
        aes_ctr_init &&
        aes_ctr_init_ready;

    // A request remains valid until accepted by aes_ctr_top.
    assign aes_stream_req =
        (state == ST_RUN) &&
        (alg_reg == ALG_AES) &&
        (aes_req_count < block_total);

    assign aes_req_fire =
        aes_stream_req &&
        aes_stream_req_ready;

    aes_ctr_top u_aes_ctr (
        .clk                (clk),
        .rst_n              (rst_n),

        .i_key_load         (aes_key_load),
        .o_key_load_ready   (aes_key_load_ready),
        .i_key              (key_reg),
        .o_key_ready        (aes_key_ready),

        .i_ctr_init         (aes_ctr_init),
        .o_ctr_init_ready   (aes_ctr_init_ready),
        .i_count            (count_reg),
        .i_bearer           (bearer_reg),
        .i_direction        (direction_reg),

        .i_stream_vld       (aes_stream_req),
        .o_stream_ready     (aes_stream_req_ready),
        .o_stream           (aes_stream),
        .o_stream_vld       (aes_stream_vld),
        .i_stream_ready     (aes_stream_ready)
    );

    // =========================================================
    // SNOW3G Interface
    // =========================================================

    wire        snow_start;
    wire        snow_start_ready;
    wire        snow_ready;

    wire        snow_stream_req;
    wire        snow_stream_req_ready;

    wire [31:0] snow_stream;
    wire        snow_stream_vld;
    wire        snow_stream_ready;

    wire        snow_busy;

    wire snow_start_fire;
    wire snow_req_fire;
    wire snow_word_fire;

    assign snow_start =
        (state == ST_SNOW_INIT);

    assign snow_start_fire =
        snow_start &&
        snow_start_ready;

    assign snow_stream_req =
        (state == ST_RUN) &&
        (alg_reg == ALG_SNOW3G) &&
        (word_req_count < word_total);

    assign snow_req_fire =
        snow_stream_req &&
        snow_stream_req_ready;

    assign snow_stream_ready =
        (state == ST_RUN) &&
        (alg_reg == ALG_SNOW3G) &&
        packer_word_ready;

    assign snow_word_fire =
        snow_stream_vld &&
        snow_stream_ready;

    snow3g_enc u_snow3g_enc (
        .clk                (clk),
        .rst_n              (rst_n),

        .i_start            (snow_start),
        .o_start_ready      (snow_start_ready),

        .i_key              (key_reg),
        .i_iv               (enc_iv),

        .o_ready            (snow_ready),

        .i_stream_req       (snow_stream_req),
        .o_stream_req_ready (snow_stream_req_ready),

        .o_stream           (snow_stream),
        .o_stream_vld       (snow_stream_vld),
        .i_stream_ready     (snow_stream_ready),

        .o_busy             (snow_busy)
    );

    // =========================================================
    // ZUC Interface
    // =========================================================

    wire        zuc_start;
    wire        zuc_start_ready;
    wire        zuc_ready;

    wire        zuc_stream_req;
    wire        zuc_stream_req_ready;

    wire [31:0] zuc_stream;
    wire        zuc_stream_vld;
    wire        zuc_stream_ready;

    wire        zuc_busy;

    wire zuc_start_fire;
    wire zuc_req_fire;
    wire zuc_word_fire;

    assign zuc_start =
        (state == ST_ZUC_INIT);

    assign zuc_start_fire =
        zuc_start &&
        zuc_start_ready;

    assign zuc_stream_req =
        (state == ST_RUN) &&
        (alg_reg == ALG_ZUC) &&
        (word_req_count < word_total);

    assign zuc_req_fire =
        zuc_stream_req &&
        zuc_stream_req_ready;

    assign zuc_stream_ready =
        (state == ST_RUN) &&
        (alg_reg == ALG_ZUC) &&
        packer_word_ready;

    assign zuc_word_fire =
        zuc_stream_vld &&
        zuc_stream_ready;

    zuc_enc u_zuc_enc (
        .clk                (clk),
        .rst_n              (rst_n),

        .i_start            (zuc_start),
        .o_start_ready      (zuc_start_ready),

        .i_key              (key_reg),
        .i_iv               (enc_iv),

        .o_ready            (zuc_ready),

        .i_stream_req       (zuc_stream_req),
        .o_stream_req_ready (zuc_stream_req_ready),

        .o_stream           (zuc_stream),
        .o_stream_vld       (zuc_stream_vld),
        .i_stream_ready     (zuc_stream_ready),

        .o_busy             (zuc_busy)
    );

    // =========================================================
    // Shared 32-bit Word Packer Input
    // =========================================================

    wire [31:0] selected_word;
    wire        selected_word_vld;
    wire        packer_word_ready;

    assign selected_word =
        (alg_reg == ALG_SNOW3G) ? snow_stream :
        (alg_reg == ALG_ZUC)    ? zuc_stream  :
                                  32'b0;

    assign selected_word_vld =
        (state == ST_RUN) &&
        (
            ((alg_reg == ALG_SNOW3G) && snow_stream_vld) ||
            ((alg_reg == ALG_ZUC)    && zuc_stream_vld)
        );

    // =========================================================
    // Shared 32-to-128 Packer
    // =========================================================

    wire        packer_clear;
    wire [127:0] packed_stream;
    wire         packed_stream_vld;
    wire         packed_stream_ready;

    assign packer_clear = (state == ST_CLEAR);

    sec_stream_packer_32to128 u_shared_packer (
        .clk            (clk),
        .rst_n          (rst_n),

        .i_clear        (packer_clear),

        .i_word         (selected_word),
        .i_word_vld     (selected_word_vld),
        .o_word_ready   (packer_word_ready),

        .o_stream       (packed_stream),
        .o_stream_vld   (packed_stream_vld),
        .i_stream_ready (packed_stream_ready)
    );

    // =========================================================
    // 128-bit Keystream Mux
    // =========================================================

    wire [127:0] selected_stream;
    wire         selected_stream_vld;
    wire         selected_stream_ready;

    sec_enc_stream_mux u_stream_mux (
        .i_alg_sel        (alg_reg),

        .i_aes_stream     (aes_stream),
        .i_aes_vld        (
            aes_stream_vld &&
            (state == ST_RUN)
        ),
        .o_aes_ready      (aes_stream_ready),

        .i_packed_stream  (packed_stream),
        .i_packed_vld     (
            packed_stream_vld &&
            (state == ST_RUN)
        ),
        .o_packed_ready   (packed_stream_ready),

        .o_stream         (selected_stream),
        .o_stream_vld     (selected_stream_vld),
        .i_stream_ready   (selected_stream_ready)
    );

    // =========================================================
    // Input Data and XOR Control
    // =========================================================

    wire data_input_enable;

    assign data_input_enable =
        (state == ST_RUN) &&
        (block_in_count < block_total);

    wire xor_data_ready;
    wire xor_stream_ready;
    wire xor_data_vld;

    assign xor_data_vld =
        i_data_vld &&
        data_input_enable;

    assign o_data_ready =
        xor_data_ready &&
        data_input_enable;

    assign selected_stream_ready =
        xor_stream_ready &&
        (state == ST_RUN);

    // =========================================================
    // Unified XOR
    // =========================================================

    wire [127:0] xor_output_data;
    wire         xor_output_vld;
    wire         xor_output_last;
    wire [4:0]   xor_output_valid_bytes;

    sec_enc_xor128 u_xor128 (
        .clk            (clk),
        .rst_n          (rst_n),

        .i_data         (i_data),
        .i_data_vld     (xor_data_vld),
        .o_data_ready   (xor_data_ready),

        .i_data_last    (i_data_last),
        .i_valid_bytes  (i_valid_bytes),

        .i_stream       (selected_stream),
        .i_stream_vld   (selected_stream_vld),
        .o_stream_ready (xor_stream_ready),

        .o_data         (xor_output_data),
        .o_data_vld     (xor_output_vld),
        .i_data_ready   (i_data_ready),

        .o_data_last    (xor_output_last),
        .o_valid_bytes  (xor_output_valid_bytes)
    );

    // =========================================================
    // Ciphertext Output
    // =========================================================

    assign o_data =
        xor_output_data;

    assign o_data_vld =
        xor_output_vld;

    assign o_data_last =
        xor_output_last;

    assign o_valid_bytes =
        xor_output_valid_bytes;

    // =========================================================
    // Stream Handshake Events
    // =========================================================

    wire input_fire;
    wire output_fire;

    wire zuc_word_fire_unused;

    assign input_fire =
        i_data_vld &&
        o_data_ready;

    assign output_fire =
        o_data_vld &&
        i_data_ready;

    assign zuc_word_fire_unused =
        zuc_word_fire;

    wire last_output_fire;

    assign last_output_fire =
        (state == ST_RUN) &&
        output_fire &&
        (block_total != 32'd0) &&
        (block_out_count == (block_total - 32'd1));

    // =========================================================
    // Main FSM and Counters
    // =========================================================

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= ST_IDLE;

            alg_reg <= ALG_NULL;
            key_reg <= 128'b0;

            count_reg <= 32'b0;
            bearer_reg <= 5'b0;
            direction_reg <= 1'b0;

            packet_bytes_reg <= 32'b0;
            block_total <= 32'b0;

            block_in_count <= 32'b0;
            block_out_count <= 32'b0;

            aes_req_count <= 32'b0;

            word_req_count <= 34'b0;
            word_recv_count <= 34'b0;

            o_done <= 1'b0;
        end else begin
            o_done <= 1'b0;

            case (state)
                ST_IDLE: begin
                    if (start_fire) begin
                        alg_reg <= i_alg_sel;
                        key_reg <= i_key;

                        count_reg <= i_count;
                        bearer_reg <= i_bearer;
                        direction_reg <= i_direction;

                        packet_bytes_reg <= i_packet_bytes;
                        block_total <= start_block_total;

                        block_in_count <= 32'b0;
                        block_out_count <= 32'b0;

                        aes_req_count <= 32'b0;
                        word_req_count <= 34'b0;
                        word_recv_count <= 34'b0;

                        state <= ST_CLEAR;
                    end
                end

                ST_CLEAR: begin
                    if (packet_bytes_reg == 32'd0) begin
                        o_done <= 1'b1;
                        state <= ST_IDLE;
                    end else begin
                        case (alg_reg)
                            ALG_AES:
                                state <= ST_AES_KEY_LOAD;

                            ALG_SNOW3G:
                                state <= ST_SNOW_INIT;

                            ALG_ZUC:
                                state <= ST_ZUC_INIT;

                            ALG_NULL:
                                state <= ST_RUN;

                            default:
                                state <= ST_IDLE;
                        endcase
                    end
                end

                // Hold key-load valid until the CTR block accepts it.
                ST_AES_KEY_LOAD: begin
                    if (aes_key_load_fire)
                        state <= ST_AES_WAIT_KEY;
                end

                // Wait for the loaded key to be available before CTR init.
                ST_AES_WAIT_KEY: begin
                    if (aes_key_ready)
                        state <= ST_AES_CTR_INIT;
                end

                // Hold CTR-init valid until the CTR block accepts it.
                ST_AES_CTR_INIT: begin
                    if (aes_ctr_init_fire)
                        state <= ST_RUN;
                end

                // Hold the SNOW3G start request until accepted.
                ST_SNOW_INIT: begin
                    if (snow_start_fire)
                        state <= ST_WAIT_INIT;
                end

                // Hold the ZUC start request until accepted.
                ST_ZUC_INIT: begin
                    if (zuc_start_fire)
                        state <= ST_WAIT_INIT;
                end

                ST_WAIT_INIT: begin
                    if (
                        ((alg_reg == ALG_SNOW3G) && snow_ready) ||
                        ((alg_reg == ALG_ZUC)    && zuc_ready)
                    )
                        state <= ST_RUN;
                end

                ST_RUN: begin
                    if (input_fire)
                        block_in_count <= block_in_count + 1'b1;

                    if (aes_req_fire)
                        aes_req_count <= aes_req_count + 1'b1;

                    if (snow_req_fire || zuc_req_fire)
                        word_req_count <= word_req_count + 1'b1;

                    if (snow_word_fire || zuc_word_fire)
                        word_recv_count <= word_recv_count + 1'b1;

                    if (output_fire)
                        block_out_count <= block_out_count + 1'b1;

                    if (last_output_fire) begin
                        o_done <= 1'b1;
                        state <= ST_IDLE;
                    end
                end

                default: begin
                    state <= ST_IDLE;
                end
            endcase
        end
    end

endmodule