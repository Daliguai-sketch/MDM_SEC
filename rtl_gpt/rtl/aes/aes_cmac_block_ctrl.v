module aes_cmac_block_ctrl (
    input  wire         clk,
    input  wire         rst_n,

    // MAC start
    input  wire         i_start,
    output wire         o_start_ready,

    // Subkeys
    input  wire [127:0] i_k1,
    input  wire [127:0] i_k2,

    // Packer interface
    input  wire [127:0] i_block,
    input  wire         i_block_vld,
    output wire         o_block_ready,

    input  wire         i_block_last,
    input  wire         i_block_complete,

    // AES input
    output wire [127:0] o_aes_block,
    output wire         o_aes_block_vld,
    input  wire         i_aes_block_ready,

    // AES final-round bypass
    input  wire [127:0] i_aes_finish_data,
    input  wire         i_aes_finish_valid,

    // MAC output
    output reg  [31:0]  o_mac,
    output reg          o_mac_vld,
    input  wire         i_mac_ready,

    // Status
    output wire         o_busy
);

// =====================================================
// Controller States
// =====================================================

localparam ST_IDLE = 2'd0;
localparam ST_RUN  = 2'd1;
localparam ST_DONE = 2'd2;

reg [1:0] state;


// =====================================================
// CBC State
// =====================================================

reg [127:0] cbc_state;

reg aes_pending;

reg pending_last;


// =====================================================
// CBC Feedback Bypass
// =====================================================

// On the final AES iteration, use the combinational
// AES result directly.
//
// Otherwise use the registered CBC state.

wire [127:0] cbc_feedback;

assign cbc_feedback =
    i_aes_finish_valid
    ? i_aes_finish_data
    : cbc_state;


// =====================================================
// Subkey Selection
// =====================================================

wire [127:0] selected_subkey;

assign selected_subkey =
    i_block_last
    ?
    (
        i_block_complete
        ? i_k1
        : i_k2
    )
    :
    128'd0;


// =====================================================
// AES Input
// =====================================================

assign o_aes_block =
    i_block ^
    selected_subkey ^
    cbc_feedback;


// =====================================================
// Start Handshake
// =====================================================

assign o_start_ready =
    (state == ST_IDLE);

wire start_accept;

assign start_accept =
    i_start &&
    o_start_ready;


// =====================================================
// AES Block Request
// =====================================================

// A new CMAC block can be accepted when:
//
// 1. Controller is running.
// 2. AES core can accept a new block.
// 3. No previous AES operation is pending,
//    OR the previous operation finishes this cycle.
// 4. Current operation is not the final operation.

wire can_launch;

assign can_launch =
    (state == ST_RUN) &&
    i_aes_block_ready &&
    (!aes_pending || i_aes_finish_valid) &&
    !(i_aes_finish_valid && pending_last);


// =====================================================
// Packer Ready
// =====================================================

assign o_block_ready =
    can_launch;


// =====================================================
// AES Request Valid
// =====================================================

assign o_aes_block_vld =
    i_block_vld &&
    can_launch;


// =====================================================
// Block Handshake
// =====================================================

wire block_accept;

assign block_accept =
    i_block_vld &&
    o_block_ready;


// =====================================================
// Status
// =====================================================

assign o_busy =
    (state != ST_IDLE);


// =====================================================
// Sequential Controller
// =====================================================

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        state <= ST_IDLE;

        cbc_state <= 128'd0;

        aes_pending <= 1'b0;

        pending_last <= 1'b0;

        o_mac <= 32'd0;

        o_mac_vld <= 1'b0;

    end
    else begin

        case (state)

            // =========================================
            // IDLE
            // =========================================

            ST_IDLE: begin

                if (start_accept) begin

                    cbc_state <= 128'd0;

                    aes_pending <= 1'b0;

                    pending_last <= 1'b0;

                    o_mac_vld <= 1'b0;

                    state <= ST_RUN;

                end

            end


            // =========================================
            // RUN
            // =========================================

            ST_RUN: begin

                // -------------------------------------
                // AES completion
                // -------------------------------------

                if (i_aes_finish_valid &&
                    aes_pending) begin

                    cbc_state <=
                        i_aes_finish_data;

                    if (pending_last) begin

                        o_mac <=
                            i_aes_finish_data[127:96];

                        o_mac_vld <= 1'b1;

                        aes_pending <= 1'b0;

                        state <= ST_DONE;

                    end
                    else begin

                        // If next block is accepted
                        // simultaneously, keep pending.

                        if (!block_accept)
                            aes_pending <= 1'b0;

                    end

                end


                // -------------------------------------
                // New AES block accepted
                // -------------------------------------

                if (block_accept) begin

                    aes_pending <= 1'b1;

                    pending_last <= i_block_last;

                end

            end


            // =========================================
            // DONE
            // =========================================

            ST_DONE: begin

                if (o_mac_vld && i_mac_ready) begin

                    o_mac_vld <= 1'b0;

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