module sec_int_top (
    input  wire         clk,
    input  wire         rst_n,

    // =====================================================
    // Transaction Start
    // =====================================================

    input  wire         i_start,
    output wire         o_start_ready,

    // =====================================================
    // Algorithm Configuration
    // =====================================================

    // 0: AES-CMAC
    // 1: SNOW3G INT
    // 2: ZUC INT
    // 3: NULL INT

    input  wire [1:0]   i_alg_sel,

    input  wire [127:0] i_key,

    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    // Actual message length in bytes
    input  wire [31:0]  i_msg_len,

    // =====================================================
    // 128-bit Message Input
    // =====================================================

    input  wire [127:0] i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,

    input  wire         i_data_last,
    input  wire [4:0]   i_valid_bytes,

    // =====================================================
    // MAC Output
    // =====================================================

    output wire [31:0]  o_mac,
    output wire         o_mac_vld,
    input  wire         i_mac_ready,

    // =====================================================
    // Status
    // =====================================================

    output wire         o_busy,
    output reg          o_done
);


// =========================================================
// Algorithm Encoding
// =========================================================

localparam ALG_AES  = 2'd0;
localparam ALG_SNOW = 2'd1;
localparam ALG_ZUC  = 2'd2;
localparam ALG_NULL = 2'd3;


// =========================================================
// FSM
// =========================================================

localparam ST_IDLE         = 4'd0;
localparam ST_CLEAR        = 4'd1;

localparam ST_AES_KEY_LOAD = 4'd2;
localparam ST_AES_WAIT_KEY = 4'd3;
localparam ST_AES_START    = 4'd4;

localparam ST_SNOW_START   = 4'd5;
localparam ST_ZUC_START    = 4'd6;

localparam ST_RUN          = 4'd7;

reg [3:0] state;


// =========================================================
// Transaction Registers
// =========================================================

reg [1:0] alg_reg;

reg [127:0] key_reg;

reg [31:0] count_reg;
reg [4:0]  bearer_reg;
reg        direction_reg;

reg [31:0] msg_len_reg;


// =========================================================
// Input Block Counters
// =========================================================

reg [31:0] block_total;
reg [31:0] block_in_count;


// =========================================================
// AES Empty Message Marker
// =========================================================

reg aes_empty_sent;


// =========================================================
// NULL INT Completion
// =========================================================

// NULL INT must consume the complete input message
// before producing the zero MAC.

wire null_message_complete;

assign null_message_complete =
    (alg_reg == ALG_NULL) &&
    (block_in_count == block_total);


// =========================================================
// Block Count
// =========================================================

wire [31:0] start_block_total;

assign start_block_total =
    (i_msg_len >> 4) +
    (|i_msg_len[3:0]);


// =========================================================
// Start / Busy
// =========================================================

assign o_start_ready =
    (state == ST_IDLE);

assign o_busy =
    (state != ST_IDLE);

wire start_fire;

assign start_fire =
    i_start && o_start_ready;


// =========================================================
// Algorithm Start Control
// =========================================================

wire aes_key_load;
wire aes_key_load_ready;
wire aes_key_ready;

wire aes_mac_start;
wire aes_mac_start_ready;

wire snow_start;
wire snow_start_ready;

wire zuc_start;
wire zuc_start_ready;

assign aes_key_load =
    (state == ST_AES_KEY_LOAD);

assign aes_mac_start =
    (state == ST_AES_START);

assign snow_start =
    (state == ST_SNOW_START);

assign zuc_start =
    (state == ST_ZUC_START);


// =========================================================
// Input Enable
// =========================================================

wire input_enable;

assign input_enable =
    (state == ST_RUN) &&
    (block_in_count < block_total);


// =========================================================
// AES Empty Message Marker
// =========================================================

wire aes_empty_enable;

assign aes_empty_enable =
    (state == ST_RUN) &&
    (alg_reg == ALG_AES) &&
    (msg_len_reg == 32'd0) &&
    !aes_empty_sent;


// =========================================================
// Splitter Input
// =========================================================

wire [127:0] splitter_data;
wire         splitter_valid;
wire         splitter_last;
wire [4:0]   splitter_bytes;

wire splitter_ready;

assign splitter_data =
    aes_empty_enable
    ? 128'b0
    : i_data;

assign splitter_valid =
    aes_empty_enable
    ? 1'b1
    : (i_data_vld && input_enable);

assign splitter_last =
    aes_empty_enable
    ? 1'b1
    : i_data_last;

assign splitter_bytes =
    aes_empty_enable
    ? 5'd0
    : i_valid_bytes;


// =========================================================
// External Input Ready
// =========================================================

assign o_data_ready =
    input_enable &&
    splitter_ready;


// =========================================================
// Input Handshake
// =========================================================

wire input_fire;

assign input_fire =
    i_data_vld &&
    o_data_ready;


// =========================================================
// AES Empty Marker Handshake
// =========================================================

wire aes_empty_fire;

assign aes_empty_fire =
    aes_empty_enable &&
    splitter_ready;


// =========================================================
// Splitter
// =========================================================

wire splitter_clear;

assign splitter_clear =
    (state == ST_CLEAR);


wire [127:0] aes_data;
wire aes_data_vld;
wire aes_data_ready;
wire aes_data_last;
wire [4:0] aes_valid_bytes;

wire [63:0] snow_data;
wire snow_data_vld;
wire snow_data_ready;
wire [3:0] snow_valid_bytes;

wire [31:0] zuc_data;
wire zuc_data_vld;
wire zuc_data_ready;
wire [2:0] zuc_valid_bytes;


sec_int_msg_splitter u_splitter (

    .clk                (clk),
    .rst_n              (rst_n),

    .i_clear            (splitter_clear),
    .i_alg_sel          (alg_reg),

    .i_data             (splitter_data),
    .i_data_vld         (splitter_valid),
    .o_data_ready       (splitter_ready),

    .i_data_last        (splitter_last),
    .i_valid_bytes      (splitter_bytes),

    .o_aes_data         (aes_data),
    .o_aes_vld          (aes_data_vld),
    .i_aes_ready        (aes_data_ready),
    .o_aes_last         (aes_data_last),
    .o_aes_valid_bytes  (aes_valid_bytes),

    .o_snow_data        (snow_data),
    .o_snow_vld         (snow_data_vld),
    .i_snow_ready       (snow_data_ready),
    .o_snow_valid_bytes (snow_valid_bytes),

    .o_zuc_data         (zuc_data),
    .o_zuc_vld          (zuc_data_vld),
    .i_zuc_ready        (zuc_data_ready),
    .o_zuc_valid_bytes  (zuc_valid_bytes)

);


// =========================================================
// AES-CMAC
// =========================================================

wire [31:0] aes_mac;
wire aes_mac_vld;
wire aes_mac_ready;

aes_cmac_top u_aes_cmac (

    .clk               (clk),
    .rst_n             (rst_n),

    .i_key_load        (aes_key_load),
    .o_key_load_ready  (aes_key_load_ready),

    .i_int_key         (key_reg),
    .o_key_ready       (aes_key_ready),

    .i_mac_start       (aes_mac_start),
    .o_mac_start_ready (aes_mac_start_ready),

    .i_count           (count_reg),
    .i_bearer          (bearer_reg),
    .i_direction       (direction_reg),

    .i_data            (aes_data),
    .i_data_vld        (aes_data_vld),
    .o_data_ready      (aes_data_ready),

    .i_data_last       (aes_data_last),
    .i_valid_bytes     (aes_valid_bytes),

    .o_mac             (aes_mac),
    .o_mac_vld         (aes_mac_vld),
    .i_mac_ready       (aes_mac_ready)

);


// =========================================================
// SNOW3G INT
// =========================================================

wire [31:0] snow_mac;
wire snow_mac_vld;
wire snow_mac_ready;
wire snow_busy;

snow3g_int u_snow_int (

    .clk           (clk),
    .rst_n         (rst_n),

    .i_start       (snow_start),
    .o_start_ready (snow_start_ready),

    .i_key         (key_reg),

    .i_count       (count_reg),
    .i_bearer      (bearer_reg),
    .i_direction   (direction_reg),

    .i_msg_len     (msg_len_reg),

    .i_data        (snow_data),
    .i_data_vld    (snow_data_vld),
    .o_data_ready  (snow_data_ready),
    .i_valid_bytes (snow_valid_bytes),

    .o_mac         (snow_mac),
    .o_mac_vld     (snow_mac_vld),
    .i_mac_ready   (snow_mac_ready),

    .o_busy        (snow_busy)

);


// =========================================================
// ZUC INT
// =========================================================

wire [31:0] zuc_mac;
wire zuc_mac_vld;
wire zuc_mac_ready;
wire zuc_busy;

zuc_int u_zuc_int (

    .clk           (clk),
    .rst_n         (rst_n),

    .i_start       (zuc_start),
    .o_start_ready (zuc_start_ready),

    .i_key         (key_reg),

    .i_count       (count_reg),
    .i_bearer      (bearer_reg),
    .i_direction   (direction_reg),

    .i_msg_len     (msg_len_reg),

    .i_data        (zuc_data),
    .i_data_vld    (zuc_data_vld),
    .o_data_ready  (zuc_data_ready),
    .i_valid_bytes (zuc_valid_bytes),

    .o_mac         (zuc_mac),
    .o_mac_vld     (zuc_mac_vld),
    .i_mac_ready   (zuc_mac_ready),

    .o_busy        (zuc_busy)

);


// =========================================================
// MAC Result MUX
// =========================================================

assign o_mac =
    (alg_reg == ALG_AES)  ? aes_mac  :
    (alg_reg == ALG_SNOW) ? snow_mac :
    (alg_reg == ALG_ZUC)  ? zuc_mac  :
                            32'b0;


// =========================================================
// MAC Valid
// =========================================================

assign o_mac_vld =
    (state == ST_RUN) &&
    (
        ((alg_reg == ALG_AES)  && aes_mac_vld)  ||
        ((alg_reg == ALG_SNOW) && snow_mac_vld) ||
        ((alg_reg == ALG_ZUC)  && zuc_mac_vld)  ||
        ((alg_reg == ALG_NULL) &&
         null_message_complete)
    );


// =========================================================
// MAC Ready Routing
// =========================================================

assign aes_mac_ready =
    (state == ST_RUN) &&
    (alg_reg == ALG_AES) &&
    i_mac_ready;

assign snow_mac_ready =
    (state == ST_RUN) &&
    (alg_reg == ALG_SNOW) &&
    i_mac_ready;

assign zuc_mac_ready =
    (state == ST_RUN) &&
    (alg_reg == ALG_ZUC) &&
    i_mac_ready;


// =========================================================
// MAC Handshake
// =========================================================

wire mac_fire;

assign mac_fire =
    o_mac_vld &&
    i_mac_ready;


// =========================================================
// FSM
// =========================================================

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        state <= ST_IDLE;

        alg_reg <= ALG_NULL;
        key_reg <= 128'b0;

        count_reg <= 32'b0;
        bearer_reg <= 5'b0;
        direction_reg <= 1'b0;

        msg_len_reg <= 32'b0;

        block_total <= 32'b0;
        block_in_count <= 32'b0;

        aes_empty_sent <= 1'b0;

        o_done <= 1'b0;

    end
    else begin

        o_done <= 1'b0;

        case (state)

            // =============================================
            // IDLE
            // =============================================

            ST_IDLE: begin

                if (start_fire) begin

                    alg_reg <= i_alg_sel;
                    key_reg <= i_key;

                    count_reg <= i_count;
                    bearer_reg <= i_bearer;
                    direction_reg <= i_direction;

                    msg_len_reg <= i_msg_len;

                    block_total <= start_block_total;
                    block_in_count <= 32'd0;

                    aes_empty_sent <= 1'b0;

                    state <= ST_CLEAR;

                end

            end


            // =============================================
            // CLEAR
            // =============================================

            ST_CLEAR: begin

                case (alg_reg)

                    ALG_AES:
                        state <= ST_AES_KEY_LOAD;

                    ALG_SNOW:
                        state <= ST_SNOW_START;

                    ALG_ZUC:
                        state <= ST_ZUC_START;

                    ALG_NULL:
                        state <= ST_RUN;

                    default:
                        state <= ST_IDLE;

                endcase

            end


            // =============================================
            // AES KEY LOAD
            // =============================================

            ST_AES_KEY_LOAD: begin

                if (aes_key_load_ready)
                    state <= ST_AES_WAIT_KEY;

            end


            // =============================================
            // AES WAIT KEY/SUBKEY
            // =============================================

            ST_AES_WAIT_KEY: begin

                if (aes_key_ready)
                    state <= ST_AES_START;

            end


            // =============================================
            // AES MAC START
            // =============================================

            ST_AES_START: begin

                if (aes_mac_start_ready)
                    state <= ST_RUN;

            end


            // =============================================
            // SNOW3G START
            // =============================================

            ST_SNOW_START: begin

                if (snow_start_ready)
                    state <= ST_RUN;

            end


            // =============================================
            // ZUC START
            // =============================================

            ST_ZUC_START: begin

                if (zuc_start_ready)
                    state <= ST_RUN;

            end


            // =============================================
            // RUN
            // =============================================

            ST_RUN: begin

                // -----------------------------------------
                // Count accepted 128-bit input blocks
                // -----------------------------------------

                if (input_fire) begin

                    block_in_count <=
                        block_in_count + 1'b1;

                end


                // -----------------------------------------
                // AES Empty Message Marker
                // -----------------------------------------

                if (aes_empty_fire)
                    aes_empty_sent <= 1'b1;


                // -----------------------------------------
                // Completion only after MAC handshake
                // -----------------------------------------

                if (mac_fire) begin

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