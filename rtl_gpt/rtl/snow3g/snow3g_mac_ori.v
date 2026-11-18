module snow3g_mac (
    input  wire         clk,
    input  wire         rst_n,

    // MAC initialization
    input  wire         i_start,
    output wire         o_start_ready,

    input  wire [63:0]  i_p,
    input  wire [63:0]  i_q,
    input  wire [31:0]  i_otp,

    // Total message length in bytes
    input  wire [31:0]  i_msg_len,

    // 64-bit message stream
    input  wire [63:0]  i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,

    // Number of valid bytes in this beat: 1..8
    input  wire [3:0]   i_valid_bytes,

    // Final MAC
    output reg  [31:0]  o_mac,
    output reg          o_mac_vld,
    input  wire         i_mac_ready,

    output wire         o_busy
);

    localparam ST_IDLE   = 2'd0;
    localparam ST_DATA   = 2'd1;
    localparam ST_LENGTH = 2'd2;
    localparam ST_OUT    = 2'd3;

    reg [1:0] state;

    reg [63:0] p_reg;
    reg [63:0] q_reg;
    reg [31:0] otp_reg;

    reg [31:0] msg_len_reg;
    reg [31:0] bytes_remaining;

    reg [63:0] eval_reg;

    wire data_fire;

    reg [63:0] masked_data;

    integer i;


    /*
     * GF(2^64) multiply by x
     */

    function [63:0] mulx64;

        input [63:0] value;

        begin

            if (value[63])
                mulx64 = {value[62:0], 1'b0} ^ 64'h1B;
            else
                mulx64 = {value[62:0], 1'b0};

        end

    endfunction


    /*
     * GF(2^64) multiplication
     *
     * Equivalent to Python eval_M().
     */

    function [63:0] eval_mul64;

        input [63:0] p;
        input [63:0] m;

        reg [63:0] result;
        reg [63:0] temp;

        integer k;

        begin

            result = 64'b0;
            temp = m;

            for (k = 0; k < 64; k = k + 1) begin

                if (p[k])
                    result = result ^ temp;

                temp = mulx64(temp);

            end

            eval_mul64 = result;

        end

    endfunction


    /*
     * Valid-byte mask
     *
     * MSB-first byte ordering.
     */

    always @(*) begin

        case (i_valid_bytes)

            4'd0: masked_data = 64'h0000000000000000;
            4'd1: masked_data = i_data & 64'hFF00000000000000;
            4'd2: masked_data = i_data & 64'hFFFF000000000000;
            4'd3: masked_data = i_data & 64'hFFFFFF0000000000;
            4'd4: masked_data = i_data & 64'hFFFFFFFF00000000;
            4'd5: masked_data = i_data & 64'hFFFFFFFFFF000000;
            4'd6: masked_data = i_data & 64'hFFFFFFFFFFFF0000;
            4'd7: masked_data = i_data & 64'hFFFFFFFFFFFFFF00;
            4'd8: masked_data = i_data;

            default:
                masked_data = 64'b0;

        endcase

    end


    assign o_start_ready =
        (state == ST_IDLE);

    assign o_data_ready =
        (state == ST_DATA);

    assign data_fire =
        i_data_vld && o_data_ready;

    assign o_busy =
        (state != ST_IDLE);


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= ST_IDLE;

            p_reg <= 64'b0;
            q_reg <= 64'b0;
            otp_reg <= 32'b0;

            msg_len_reg <= 32'b0;
            bytes_remaining <= 32'b0;

            eval_reg <= 64'b0;

            o_mac <= 32'b0;
            o_mac_vld <= 1'b0;

        end
        else begin

            case (state)

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


                ST_DATA: begin

                    if (data_fire) begin

                        eval_reg <= eval_mul64(
                            p_reg,
                            eval_reg ^ masked_data
                        );

                        bytes_remaining <=
                            bytes_remaining - i_valid_bytes;

                        if (bytes_remaining <= i_valid_bytes)
                            state <= ST_LENGTH;

                    end

                end


                ST_LENGTH: begin

                    /*
                     * Python:
                     *
                     * msg.append(data_len << 3)
                     *
                     * Length encoded as 64-bit Bit Length.
                     */

                    eval_reg <= eval_mul64(
                        q_reg,
                        eval_reg ^ {29'b0, msg_len_reg, 3'b0}
                    );

                    state <= ST_OUT;

                end


                ST_OUT: begin

                    /*
                     * eval_reg contains the result of
                     * the final multiplication.
                     */

                    o_mac <= eval_reg[63:32] ^ otp_reg;

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