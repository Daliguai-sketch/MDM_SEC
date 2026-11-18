module aes_ctr_top (
    input  wire         clk,
    input  wire         rst_n,

    // =====================================================
    // Key Configuration
    // =====================================================
    input  wire         i_key_load,
    output wire         o_key_load_ready,

    input  wire [127:0] i_key,
    output wire         o_key_ready,

    // =====================================================
    // CTR Configuration
    // =====================================================
    input  wire         i_ctr_init,
    output wire         o_ctr_init_ready,

    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    // =====================================================
    // Stream Request
    // =====================================================
    input  wire         i_stream_vld,
    output wire         o_stream_ready,

    // =====================================================
    // Keystream Output
    // =====================================================
    output wire [127:0] o_stream,
    output wire         o_stream_vld,
    input  wire         i_stream_ready
);

// =========================================================
// Internal Registers
// =========================================================

// 13-bit counter, same as Python Golden Model
reg [12:0] counter_reg;

// CTR configuration registers
reg [31:0] count_reg;
reg [4:0]  bearer_reg;
reg        direction_reg;

// Indicates that CTR parameters have been initialized
reg ctr_config_valid;


// =========================================================
// AES Core Interface
// =========================================================

wire core_block_ready;
wire core_busy;

wire core_key_load_ready;
wire core_key_ready;

wire [127:0] core_block_out;
wire         core_block_valid;


// =========================================================
// Key Configuration
// =========================================================

assign o_key_load_ready = core_key_load_ready;

assign o_key_ready = core_key_ready;


// =========================================================
// CTR Initialization Ready
// =========================================================

// CTR can be reconfigured only when:
//
// 1. AES key is ready
// 2. AES datapath is idle
// 3. No key loading request
// 4. No pending CTR initialization
//
// This prevents mixing keystreams from different packets.

assign o_ctr_init_ready =
    core_key_ready &&
    !core_busy &&
    !i_key_load;


// =========================================================
// CTR Initialization Handshake
// =========================================================

wire ctr_init_accept;

assign ctr_init_accept =
    i_ctr_init && o_ctr_init_ready;


// =========================================================
// Stream Request Ready
// =========================================================

// Stream generation is allowed only after CTR parameters
// have been initialized.
//
// Prevent accepting stream requests during CTR reconfiguration.

assign o_stream_ready =
    core_block_ready &&
    ctr_config_valid &&
    !i_ctr_init &&
    !i_key_load;


// =========================================================
// Stream Request Handshake
// =========================================================

wire stream_accept;

assign stream_accept =
    i_stream_vld && o_stream_ready;


// =========================================================
// Counter Block Generation
// =========================================================

// Python reference:
//
// enc_iv0 = count
// enc_iv1 = (bearer << 27) | (direction << 26)
// enc_iv2 = 0
// enc_iv3 = counter & 0x1FFF
//
// 128-bit layout:
//
// [127:96] COUNT
// [95:64]  BEARER + DIRECTION + RESERVED
// [63:32]  ZERO
// [31:0]   COUNTER

wire [127:0] counter_block;

assign counter_block = {

    count_reg,

    bearer_reg,
    direction_reg,
    26'b0,

    32'b0,

    19'b0,
    counter_reg

};


// =========================================================
// AES-128 5-Cycle Core
// =========================================================

aes_core_5cycle u_aes_core (

    .clk               (clk),
    .rst_n             (rst_n),

    // Key
    .i_key_load        (i_key_load),
    .o_key_load_ready  (core_key_load_ready),
    .i_key             (i_key),
    .o_key_ready       (core_key_ready),

    // Block request
    .i_block_vld       (i_stream_vld && o_stream_ready),

    .o_block_ready     (core_block_ready),

    .i_block           (counter_block),

    // Block output
    .o_block           (core_block_out),
    .o_block_vld       (core_block_valid),
    .i_block_ready     (i_stream_ready),

    .o_finish_data     (),
    .o_finish_valid    (),
    // Core status
    .o_busy            (core_busy)

);


// =========================================================
// Keystream Output
// =========================================================

assign o_stream     = core_block_out;
assign o_stream_vld = core_block_valid;


// =========================================================
// CTR Registers
// =========================================================

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        counter_reg <= 13'd0;

        count_reg <= 32'd0;
        bearer_reg <= 5'd0;
        direction_reg <= 1'b0;

        ctr_config_valid <= 1'b0;

    end
    else begin

        // -------------------------------------------------
        // New Key
        // -------------------------------------------------
        //
        // A new key invalidates the current CTR context.
        // CTR must be initialized again before generating
        // a new keystream.
        //
        // Key request is accepted only when the AES core
        // asserts key_load_ready.

        if (i_key_load && core_key_load_ready) begin

            counter_reg <= 13'd0;

            ctr_config_valid <= 1'b0;

        end

        // -------------------------------------------------
        // CTR Initialization
        // -------------------------------------------------

        else if (ctr_init_accept) begin

            count_reg <= i_count;

            bearer_reg <= i_bearer;

            direction_reg <= i_direction;

            counter_reg <= 13'd0;

            ctr_config_valid <= 1'b1;

        end

        // -------------------------------------------------
        // Stream Request Accepted
        // -------------------------------------------------

        else if (stream_accept) begin

            counter_reg <= counter_reg + 13'd1;

        end

    end

end

endmodule