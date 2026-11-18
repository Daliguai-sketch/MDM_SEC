module aes_cmac_top (
    input  wire         clk,
    input  wire         rst_n,

    // =====================================================
    // Key Interface
    // =====================================================
    input  wire         i_key_load,
    output wire         o_key_load_ready,
    input  wire [127:0] i_int_key,
    output wire         o_key_ready,

    // =====================================================
    // MAC Start
    // =====================================================
    input  wire         i_mac_start,
    output wire         o_mac_start_ready,

    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    // =====================================================
    // Message Input
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
    input  wire         i_mac_ready
);

// =========================================================
// FSM
// =========================================================

localparam ST_IDLE        = 3'd0;
localparam ST_KEY_WAIT    = 3'd1;
localparam ST_SUBKEY_REQ  = 3'd2;
localparam ST_SUBKEY_WAIT = 3'd3;
localparam ST_READY       = 3'd4;

reg [2:0] state;

// =========================================================
// AES Core Signals
// =========================================================

wire         aes_key_load_ready;
wire         aes_key_ready;

wire         aes_block_ready;

wire [127:0] aes_block_out;
wire         aes_block_out_valid;

wire [127:0] aes_finish_data;
wire         aes_finish_valid;

wire         aes_busy;

// =========================================================
// Subkey Registers
// =========================================================

reg [127:0] subkey_k1;
reg [127:0] subkey_k2;

wire [127:0] subkey_k1_comb;
wire [127:0] subkey_k2_comb;

aes_cmac_subkey u_subkey (
    .i_l  (aes_block_out),
    .o_k1 (subkey_k1_comb),
    .o_k2 (subkey_k2_comb)
);

// =========================================================
// Packer Signals
// =========================================================

wire [127:0] packer_block;
wire         packer_block_valid;
wire         packer_block_ready;

wire         packer_block_last;
wire         packer_block_complete;

wire         packer_busy;
wire         packer_start_ready;

// =========================================================
// Block Controller Signals
// =========================================================

wire         ctrl_start_ready;
wire         ctrl_busy;

wire [127:0] ctrl_aes_block;
wire         ctrl_aes_block_valid;

wire         ctrl_aes_block_ready;

wire [31:0]  ctrl_mac;
wire         ctrl_mac_valid;

// =========================================================
// Key Interface
// =========================================================

assign o_key_load_ready =
    (state == ST_IDLE || state == ST_READY) &&
    aes_key_load_ready &&
    !ctrl_busy &&
    !packer_busy;

wire key_load_accept;

assign key_load_accept =
    i_key_load &&
    o_key_load_ready;

assign o_key_ready =
    (state == ST_READY);

// =========================================================
// MAC Start
// =========================================================

assign o_mac_start_ready =
    (state == ST_READY) &&
    ctrl_start_ready &&
    packer_start_ready &&
    !i_key_load;

wire mac_start_accept;

assign mac_start_accept =
    i_mac_start &&
    o_mac_start_ready;

// =========================================================
// AES Core Input MUX
// =========================================================

// During subkey generation:
// AES input = 0
//
// During normal MAC operation:
// AES input = CBC controller output

wire subkey_request;

assign subkey_request =
    (state == ST_SUBKEY_REQ);

wire [127:0] aes_block_in;

wire aes_block_in_valid;

assign aes_block_in =
    subkey_request
    ? 128'd0
    : ctrl_aes_block;

assign aes_block_in_valid =
    subkey_request
    ? 1'b1
    : ctrl_aes_block_valid;

assign ctrl_aes_block_ready =
    aes_block_ready &&
    (state == ST_READY);

// =========================================================
// AES Core Instance
// =========================================================

aes_core_5cycle u_aes_int_core (
    .clk               (clk),
    .rst_n             (rst_n),

    .i_key_load        (key_load_accept),
    .o_key_load_ready  (aes_key_load_ready),
    .i_key             (i_int_key),
    .o_key_ready       (aes_key_ready),

    .i_block_vld       (aes_block_in_valid),
    .o_block_ready     (aes_block_ready),
    .i_block           (aes_block_in),

    .o_block           (aes_block_out),
    .o_block_vld       (aes_block_out_valid),
    .i_block_ready     (1'b1),

    .o_finish_data     (aes_finish_data),
    .o_finish_valid    (aes_finish_valid),

    .o_busy            (aes_busy)
);

// =========================================================
// CMAC Packer
// =========================================================

aes_cmac_packer u_packer (
    .clk              (clk),
    .rst_n            (rst_n),

    .i_start          (mac_start_accept),
    .o_start_ready    (packer_start_ready),

    .i_count          (i_count),
    .i_bearer         (i_bearer),
    .i_direction      (i_direction),

    .i_data           (i_data),
    .i_data_vld       (i_data_vld),
    .o_data_ready     (o_data_ready),

    .i_data_last      (i_data_last),
    .i_valid_bytes    (i_valid_bytes),

    .o_block          (packer_block),
    .o_block_vld      (packer_block_valid),
    .i_block_ready    (packer_block_ready),

    .o_block_last     (packer_block_last),
    .o_block_complete (packer_block_complete),

    .o_busy           (packer_busy)
);

// =========================================================
// CMAC Block Controller
// =========================================================

aes_cmac_block_ctrl u_block_ctrl (
    .clk                (clk),
    .rst_n              (rst_n),

    .i_start            (mac_start_accept),
    .o_start_ready      (ctrl_start_ready),

    .i_k1               (subkey_k1),
    .i_k2               (subkey_k2),

    .i_block            (packer_block),
    .i_block_vld        (packer_block_valid),
    .o_block_ready      (packer_block_ready),

    .i_block_last       (packer_block_last),
    .i_block_complete   (packer_block_complete),

    .o_aes_block        (ctrl_aes_block),
    .o_aes_block_vld    (ctrl_aes_block_valid),
    .i_aes_block_ready  (ctrl_aes_block_ready),

    .i_aes_finish_data  (aes_finish_data),
    .i_aes_finish_valid (aes_finish_valid),

    .o_mac              (ctrl_mac),
    .o_mac_vld          (ctrl_mac_valid),
    .i_mac_ready        (i_mac_ready),

    .o_busy             (ctrl_busy)
);

// =========================================================
// MAC Output
// =========================================================

assign o_mac = ctrl_mac;
assign o_mac_vld = ctrl_mac_valid;

// =========================================================
// Top FSM
// =========================================================

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        state <= ST_IDLE;

        subkey_k1 <= 128'd0;
        subkey_k2 <= 128'd0;

    end
    else begin

        case (state)

            // =========================================
            // IDLE
            // =========================================

            ST_IDLE: begin

                if (key_load_accept) begin
                    state <= ST_KEY_WAIT;
                end

            end

            // =========================================
            // Wait AES Key Expansion
            // =========================================

            ST_KEY_WAIT: begin

                if (aes_key_ready) begin
                    state <= ST_SUBKEY_REQ;
                end

            end

            // =========================================
            // Request AES(K,0)
            // =========================================

            ST_SUBKEY_REQ: begin

                if (aes_block_ready) begin
                    state <= ST_SUBKEY_WAIT;
                end

            end

            // =========================================
            // Wait AES(K,0)
            // =========================================

            ST_SUBKEY_WAIT: begin

                if (aes_block_out_valid) begin

                    subkey_k1 <= subkey_k1_comb;
                    subkey_k2 <= subkey_k2_comb;

                    state <= ST_READY;

                end

            end

            // =========================================
            // Ready for MAC
            // =========================================

            ST_READY: begin

                if (key_load_accept) begin
                    state <= ST_KEY_WAIT;
                end

            end

            default: begin
                state <= ST_IDLE;
            end

        endcase

    end

end

endmodule