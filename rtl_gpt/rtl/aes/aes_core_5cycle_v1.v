// ============================================================================
// Module Name : aes_core_5cycle
// Description : Area-Optimized 5-Cycle AES Core (On-the-fly Key & Comp S-Box)
// Standard    : Verilog-2001
// ============================================================================

module aes_core_5cycle (
    input  wire         clk,
    input  wire         rst_n,

    // Key interface
    input  wire         i_key_load,
    output wire         o_key_load_ready,
    input  wire [127:0] i_key,
    output wire         o_key_ready,

    // Block input
    input  wire         i_block_vld,
    output wire         o_block_ready,
    input  wire [127:0] i_block,

    // Registered block output
    output wire [127:0] o_block,
    output wire         o_block_vld,
    input  wire         i_block_ready,

    // Final round bypass
    output wire [127:0] o_finish_data,
    output wire         o_finish_valid,

    // Status
    output wire         o_busy
);

// =====================================================
// Key Registers
// =====================================================

reg [127:0] key_reg;
reg         key_loading;
reg         key_ready_reg;

// =====================================================
// On-the-fly Round Key Generation
// =====================================================

reg  [127:0] current_rk_reg;
wire [127:0] rk_a;
wire [127:0] rk_b;

// Combinational Rcon lookup
function [7:0] get_rcon;
    input [3:0] idx;
    begin
        case (idx)
            4'd1:  get_rcon = 8'h01;
            4'd2:  get_rcon = 8'h02;
            4'd3:  get_rcon = 8'h04;
            4'd4:  get_rcon = 8'h08;
            4'd5:  get_rcon = 8'h10;
            4'd6:  get_rcon = 8'h20;
            4'd7:  get_rcon = 8'h40;
            4'd8:  get_rcon = 8'h80;
            4'd9:  get_rcon = 8'h1B;
            4'd10: get_rcon = 8'h36;
            default: get_rcon = 8'h00;
        endcase
    end
endfunction

reg [2:0] round_pair_cnt;

wire [7:0] rcon_a = get_rcon({round_pair_cnt, 1'b0} + 4'd1);
wire [7:0] rcon_b = get_rcon({round_pair_cnt, 1'b0} + 4'd2);

// Step 1: Generate Round Key A
aes_key_expand_step u_key_step_a (
    .i_key      (current_rk_reg),
    .i_rcon     (rcon_a),
    .o_next_key (rk_a)
);

// Step 2: Generate Round Key B
aes_key_expand_step u_key_step_b (
    .i_key      (rk_a),
    .i_rcon     (rcon_b),
    .o_next_key (rk_b)
);

// =====================================================
// AES Datapath
// =====================================================

reg [127:0] state_reg;
reg         busy;
wire [127:0] double_round_out;

// =====================================================
// Double Round
// =====================================================

aes_double_round u_double_round (
    .state_in     (state_reg),
    .round_key_a  (rk_a),
    .round_key_b  (rk_b),
    .last_round_b (round_pair_cnt == 3'd4),
    .state_out    (double_round_out)
);

// =====================================================
// Output Registers
// =====================================================

reg [127:0] output_reg;
reg         output_valid_reg;

assign o_block = output_reg;
assign o_block_vld = output_valid_reg;

// =====================================================
// Finish Detection
// =====================================================

wire finish_cycle;
wire output_slot_available;

assign finish_cycle = 
    busy && 
    (round_pair_cnt == 3'd4);

assign output_slot_available = 
    !output_valid_reg || 
    i_block_ready;

// =====================================================
// Final Round Bypass
// =====================================================

assign o_finish_valid = 
    finish_cycle && 
    output_slot_available;

assign o_finish_data = 
    double_round_out;

// =====================================================
// Key Handshake
// =====================================================

assign o_key_load_ready = 
    !busy && 
    !output_valid_reg && 
    !key_loading;

assign o_key_ready = 
    key_ready_reg;

wire key_load_accept;

assign key_load_accept = 
    i_key_load && 
    o_key_load_ready;

// =====================================================
// Block Input Handshake
// =====================================================

assign o_block_ready = 
    key_ready_reg && 
    !key_loading && 
    !i_key_load && 
    output_slot_available && 
    (!busy || finish_cycle);

wire block_accept;

assign block_accept = 
    i_block_vld && 
    o_block_ready;

// =====================================================
// Busy
// =====================================================

assign o_busy = 
    busy || 
    output_valid_reg;

// =====================================================
// Key Control (Fakes original expansion latency)
// =====================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        key_reg <= 128'd0;
        key_loading <= 1'b0;
        key_ready_reg <= 1'b0;
    end
    else begin
        if (key_load_accept) begin
            key_reg <= i_key;
            key_loading <= 1'b1;
            key_ready_reg <= 1'b0;
        end
        // Because we expand on-the-fly, there's no actual delay needed.
        // We clear loading flag immediately next cycle to meet handshake logic.
        else if (key_loading) begin
            key_loading <= 1'b0;
            key_ready_reg <= 1'b1;
        end
    end
end

// =====================================================
// AES Processing with On-the-fly Key Updates
// =====================================================

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
        state_reg        <= 128'd0;
        current_rk_reg   <= 128'd0;
        round_pair_cnt   <= 3'd0;
        busy             <= 1'b0;
        output_reg       <= 128'd0;
        output_valid_reg <= 1'b0;
    end
    else begin
        // Output consumed
        if (output_valid_reg && i_block_ready)
            output_valid_reg <= 1'b0;

        if (busy) begin
            // -----------------------------------------
            // Final iteration
            // -----------------------------------------
            if (round_pair_cnt == 3'd4) begin
                if (output_slot_available) begin
                    output_reg <= double_round_out;
                    output_valid_reg <= 1'b1;

                    // Start next AES block immediately (Pipeline bubble avoidance)
                    if (block_accept) begin
                        state_reg      <= i_block ^ key_reg;
                        current_rk_reg <= key_reg; // Reset RK tracker back to RK0
                        round_pair_cnt <= 3'd0;
                        busy           <= 1'b1;
                    end
                    else begin
                        round_pair_cnt <= 3'd0;
                        busy           <= 1'b0;
                    end
                end
            end
            // -----------------------------------------
            // Normal iteration
            // -----------------------------------------
            else begin
                state_reg      <= double_round_out;
                current_rk_reg <= rk_b; // Roll the RK window forward for the next cycle
                round_pair_cnt <= round_pair_cnt + 1'b1;
            end
        end
        // ---------------------------------------------
        // Idle: accept new AES block
        // ---------------------------------------------
        else if (block_accept) begin
            state_reg      <= i_block ^ key_reg;
            current_rk_reg <= key_reg; // Setup initial RK tracker (RK0)
            round_pair_cnt <= 3'd0;
            busy           <= 1'b1;
        end
    end
end

endmodule