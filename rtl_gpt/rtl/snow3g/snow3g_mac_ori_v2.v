module snow3g_mac (
    input  wire         clk,
    input  wire         rst_n,

    // =====================================================
    // MAC Initialization
    // =====================================================
    input  wire         i_start,
    output wire         o_start_ready,

    input  wire [63:0]  i_p,
    input  wire [63:0]  i_q,
    input  wire [31:0]  i_otp,

    input  wire [31:0]  i_msg_len,

    // =====================================================
    // Message Input
    // =====================================================
    input  wire [63:0]  i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,

    input  wire [3:0]   i_valid_bytes,

    // =====================================================
    // MAC Output
    // =====================================================
    output reg  [31:0]  o_mac,
    output reg          o_mac_vld,
    input  wire         i_mac_ready,

    output wire         o_busy
);

    // =====================================================
    // State Definition
    // =====================================================

    localparam ST_IDLE      = 3'd0;
    localparam ST_DATA      = 3'd1;
    localparam ST_DATA_MUL2 = 3'd2;
    localparam ST_LENGTH    = 3'd3;
    localparam ST_LENGTH_MUL2 = 3'd4;
    localparam ST_OUT       = 3'd5;

    reg [2:0] state;

    // =====================================================
    // Configuration Registers
    // =====================================================

    reg [63:0] p_reg;
    reg [63:0] q_reg;

    reg [31:0] otp_reg;
    reg [31:0] msg_len_reg;
    reg [31:0] bytes_remaining;

    reg [63:0] eval_reg;

    // =====================================================
    // Shared GF64 32-Step Intermediate Registers
    // =====================================================

    reg [63:0] mul_p_reg;
    reg [63:0] mul_v_reg;
    reg [63:0] mul_acc_reg;

    // =====================================================
    // GF(2^64) Multiply by X
    // =====================================================

    function [63:0] mulx64;

        input [63:0] value;

        begin

            mulx64 =
                {value[62:0], 1'b0} ^
                (value[63] ? 64'h1B : 64'h0);

        end

    endfunction

    // =====================================================
    // Shared 32-Step GF64 Multiply
    //
    // Inputs:
    //   p   : 64-bit multiplier
    //   v   : current GF64 value
    //   acc : accumulated result
    //
    // Output:
    //   {next_v, next_acc}
    //
    // 32 iterations per combinational pass.
    // =====================================================

    function [127:0] gf64_step32;

        input [63:0] p;
        input [63:0] v;
        input [63:0] acc;

        reg [63:0] temp_v;
        reg [63:0] temp_acc;

        integer k;

        begin

            temp_v = v;
            temp_acc = acc;

            for (k = 0; k < 32; k = k + 1) begin

                if (p[k])
                    temp_acc = temp_acc ^ temp_v;

                temp_v = mulx64(temp_v);

            end

            gf64_step32 = {
                temp_v,
                temp_acc
            };

        end

    endfunction

    // =====================================================
    // Shared Step32 Input MUX
    // =====================================================

    wire [63:0] step_p;
    wire [63:0] step_v;
    wire [63:0] step_acc;

    wire [127:0] step_result;

    wire [63:0] step_next_v;
    wire [63:0] step_next_acc;

    wire mul_second_half;

    assign mul_second_half =
        (state == ST_DATA_MUL2) ||
        (state == ST_LENGTH_MUL2);

    assign step_p =
        mul_second_half
        ? mul_p_reg
        : (
            (state == ST_LENGTH)
            ? q_reg
            : p_reg
        );

    assign step_v =
        mul_second_half
        ? mul_v_reg
        : (
            (state == ST_LENGTH)
            ? (eval_reg ^ {29'b0, msg_len_reg, 3'b0})
            : (eval_reg ^ masked_data)
        );

    assign step_acc =
        mul_second_half
        ? mul_acc_reg
        : 64'b0;

    assign step_result =
        gf64_step32(
            step_p,
            step_v,
            step_acc
        );

    assign step_next_v =
        step_result[127:64];

    assign step_next_acc =
        step_result[63:0];

    // =====================================================
    // Valid Byte Mask
    // =====================================================

    reg [63:0] masked_data;

    always @(*) begin

        case (i_valid_bytes)

            4'd0:
                masked_data = 64'h0000000000000000;

            4'd1:
                masked_data = i_data & 64'hFF00000000000000;

            4'd2:
                masked_data = i_data & 64'hFFFF000000000000;

            4'd3:
                masked_data = i_data & 64'hFFFFFF0000000000;

            4'd4:
                masked_data = i_data & 64'hFFFFFFFF00000000;

            4'd5:
                masked_data = i_data & 64'hFFFFFFFFFF000000;

            4'd6:
                masked_data = i_data & 64'hFFFFFFFFFFFF0000;

            4'd7:
                masked_data = i_data & 64'hFFFFFFFFFFFFFF00;

            4'd8:
                masked_data = i_data;

            default:
                masked_data = 64'b0;

        endcase

    end

    // =====================================================
    // Handshake
    // =====================================================

    assign o_start_ready =
        (state == ST_IDLE);

    assign o_data_ready =
        (state == ST_DATA);

    assign o_busy =
        (state != ST_IDLE);

    wire data_fire;

    assign data_fire =
        i_data_vld &&
        o_data_ready;

    // =====================================================
    // Sequential FSM
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= ST_IDLE;

            p_reg <= 64'b0;
            q_reg <= 64'b0;

            otp_reg <= 32'b0;
            msg_len_reg <= 32'b0;
            bytes_remaining <= 32'b0;

            eval_reg <= 64'b0;

            mul_p_reg <= 64'b0;
            mul_v_reg <= 64'b0;
            mul_acc_reg <= 64'b0;

            o_mac <= 32'b0;
            o_mac_vld <= 1'b0;

        end
        else begin

            case (state)

                // =========================================
                // IDLE
                // =========================================

                ST_IDLE: begin

                    o_mac_vld <= 1'b0;

                    if (i_start && o_start_ready) begin

                        p_reg <= i_p;
                        q_reg <= i_q;

                        otp_reg <= i_otp;

                        msg_len_reg <= i_msg_len;
                        bytes_remaining <= i_msg_len;

                        eval_reg <= 64'b0;

                        if (i_msg_len == 32'd0)
                            state <= ST_LENGTH;
                        else
                            state <= ST_DATA;

                    end

                end

                // =========================================
                // DATA: First 32 Steps
                //
                // Performed on data handshake cycle.
                // =========================================

                ST_DATA: begin

                    if (data_fire) begin

                        // Save upper 32 multiplier bits
                        // for second half.
                        mul_p_reg <= p_reg >> 32;

                        // Save Step 0~31 result
                        mul_v_reg <= step_next_v;
                        mul_acc_reg <= step_next_acc;

                        bytes_remaining <=
                            bytes_remaining -
                            i_valid_bytes;

                        state <= ST_DATA_MUL2;

                    end

                end

                // =========================================
                // DATA: Second 32 Steps
                // =========================================

                ST_DATA_MUL2: begin

                    eval_reg <= step_next_acc;

                    if (bytes_remaining == 0)
                        state <= ST_LENGTH;
                    else
                        state <= ST_DATA;

                end

                // =========================================
                // LENGTH: First 32 Steps
                // =========================================

                ST_LENGTH: begin

                    mul_p_reg <= q_reg >> 32;

                    mul_v_reg <= step_next_v;
                    mul_acc_reg <= step_next_acc;

                    state <= ST_LENGTH_MUL2;

                end

                // =========================================
                // LENGTH: Second 32 Steps
                // =========================================

                ST_LENGTH_MUL2: begin

                    eval_reg <= step_next_acc;

                    state <= ST_OUT;

                end

                // =========================================
                // OUTPUT
                // =========================================

                ST_OUT: begin

                    o_mac <=
                        eval_reg[63:32] ^
                        otp_reg;

                    o_mac_vld <= 1'b1;

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