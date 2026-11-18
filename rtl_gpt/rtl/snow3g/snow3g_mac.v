module snow3g_mac (
    input wire clk,
    input wire rst_n,

    input wire i_start,
    output wire o_start_ready,

    input wire [63:0] i_p,
    input wire [63:0] i_q,
    input wire [31:0] i_otp,

    input wire [31:0] i_msg_len,

    input wire [63:0] i_data,
    input wire i_data_vld,
    output wire o_data_ready,
    input wire [3:0] i_valid_bytes,

    output reg [31:0] o_mac,
    output reg o_mac_vld,
    input wire i_mac_ready,

    output wire o_busy
);

localparam ST_IDLE        = 3'd0;
localparam ST_DATA        = 3'd1;
localparam ST_DATA_MUL2   = 3'd2;
localparam ST_LENGTH      = 3'd3;
localparam ST_LENGTH_MUL2 = 3'd4;
localparam ST_OUT         = 3'd5;

reg [2:0] state;

reg [63:0] p_reg;
reg [63:0] q_reg;
reg [31:0] otp_reg;

reg [31:0] msg_len_reg;
reg [31:0] bytes_remaining;

reg [63:0] eval_reg;

reg [31:0] mul_p_reg;
reg [63:0] mul_v_reg;
reg [63:0] mul_acc_reg;

wire [63:0] step_p;
wire [63:0] step_v;
wire [63:0] step_acc;

wire [63:0] step_next_v;
wire [63:0] step_next_acc;

wire mul_second_half;

wire data_fire;

reg [63:0] masked_data;

integer b;

assign o_start_ready = (state == ST_IDLE);

assign o_data_ready =
    (state == ST_DATA);

assign o_busy = (state != ST_IDLE);

assign data_fire =
    i_data_vld && o_data_ready;

assign mul_second_half =
    (state == ST_DATA_MUL2) ||
    (state == ST_LENGTH_MUL2);


// ------------------------------------------------------------
// Data Mask
//
// MSB-first:
// i_data[63:56] = Byte0
// ...
// i_data[7:0]   = Byte7
// ------------------------------------------------------------

always @(*) begin
    masked_data = 64'b0;

    for (b = 0; b < 8; b = b + 1) begin
        if (b < i_valid_bytes)
            masked_data[63-b*8 -: 8] =
                i_data[63-b*8 -: 8];
    end
end


// ------------------------------------------------------------
// Shared GF64 32-Step Unit
// ------------------------------------------------------------

assign step_p =
    mul_second_half
    ? {32'b0, mul_p_reg}
    : ((state == ST_LENGTH) ? q_reg : p_reg);

assign step_v =
    mul_second_half
    ? mul_v_reg
    : ((state == ST_LENGTH)
       ? (eval_reg ^ {29'b0, msg_len_reg, 3'b0})
       : (eval_reg ^ masked_data));

assign step_acc =
    mul_second_half ? mul_acc_reg : 64'b0;


snow3g_gf64_step32 u_gf64_step32 (
    .i_p   (step_p),
    .i_v   (step_v),
    .i_acc (step_acc),

    .o_v   (step_next_v),
    .o_acc (step_next_acc)
);


// ------------------------------------------------------------
// FSM
// ------------------------------------------------------------

always @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin

        state <= ST_IDLE;

        p_reg <= 64'b0;
        q_reg <= 64'b0;
        otp_reg <= 32'b0;

        msg_len_reg <= 32'b0;
        bytes_remaining <= 32'b0;

        eval_reg <= 64'b0;

        mul_p_reg <= 32'b0;
        mul_v_reg <= 64'b0;
        mul_acc_reg <= 64'b0;

        o_mac <= 32'b0;
        o_mac_vld <= 1'b0;

    end
    else begin

        case (state)

            // ------------------------------------------------
            // IDLE
            // ------------------------------------------------

            ST_IDLE: begin

                o_mac_vld <= 1'b0;

                if (i_start && o_start_ready) begin

                    p_reg <= i_p;
                    q_reg <= i_q;
                    otp_reg <= i_otp;

                    msg_len_reg <= i_msg_len;
                    bytes_remaining <= i_msg_len;

                    eval_reg <= 64'b0;

                    mul_p_reg <= 32'b0;
                    mul_v_reg <= 64'b0;
                    mul_acc_reg <= 64'b0;

                    if (i_msg_len == 0)
                        state <= ST_LENGTH;
                    else
                        state <= ST_DATA;

                end
            end


            // ------------------------------------------------
            // DATA - GF64 Step 0..31
            // ------------------------------------------------

            ST_DATA: begin

                if (data_fire) begin

                    mul_p_reg <= p_reg[63:32];
                    mul_v_reg <= step_next_v;
                    mul_acc_reg <= step_next_acc;

                    bytes_remaining <=
                        bytes_remaining - i_valid_bytes;

                    state <= ST_DATA_MUL2;

                end
            end


            // ------------------------------------------------
            // DATA - GF64 Step 32..63
            // ------------------------------------------------

            ST_DATA_MUL2: begin

                eval_reg <= step_next_acc;

                if (bytes_remaining == 0)
                    state <= ST_LENGTH;
                else
                    state <= ST_DATA;

            end


            // ------------------------------------------------
            // LENGTH - GF64 Step 0..31
            // ------------------------------------------------

            ST_LENGTH: begin

                mul_p_reg <= q_reg[63:32];
                mul_v_reg <= step_next_v;
                mul_acc_reg <= step_next_acc;

                state <= ST_LENGTH_MUL2;

            end


            // ------------------------------------------------
            // LENGTH - GF64 Step 32..63
            // ------------------------------------------------

            ST_LENGTH_MUL2: begin

                eval_reg <= step_next_acc;

                state <= ST_OUT;

            end


            // ------------------------------------------------
            // OUTPUT
            // ------------------------------------------------

            ST_OUT: begin

                if (!o_mac_vld) begin

                    o_mac <= eval_reg[63:32] ^ otp_reg;
                    o_mac_vld <= 1'b1;

                end
                else if (i_mac_ready) begin

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