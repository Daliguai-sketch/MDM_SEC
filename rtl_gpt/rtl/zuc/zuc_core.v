module zuc_core (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         i_init,
    output wire         o_init_ready,

    input  wire [127:0] i_key,
    input  wire [127:0] i_iv,

    output wire         o_core_ready,

    input  wire         i_stream_req,
    output wire         o_stream_req_ready,

    output wire [31:0]  o_stream,
    output wire         o_stream_vld,
    input  wire         i_stream_ready,

    output wire         o_busy
);

    /*
     * FSM
     */

    localparam ST_IDLE    = 2'd0;
    localparam ST_INIT    = 2'd1;
    localparam ST_DISCARD = 2'd2;
    localparam ST_GEN     = 2'd3;

    reg [1:0] state;

    reg [5:0] init_cnt;


    /*
     * 16 x 31-bit LFSR
     */

    reg [30:0] s [0:15];


    /*
     * F registers
     */

    reg [31:0] r1;
    reg [31:0] r2;


    /*
     * Output register
     */

    reg [31:0] stream_reg;
    reg        stream_valid_reg;


    /*
     * Bit reorganization
     */

    wire [31:0] x0;
    wire [31:0] x1;
    wire [31:0] x2;
    wire [31:0] x3;


    /*
     * F function
     */

    wire [31:0] w;
    wire [31:0] r1_next;
    wire [31:0] r2_next;


    /*
     * LFSR feedback
     */

    wire [30:0] feedback_base;
    wire [30:0] feedback_init;
    wire [30:0] feedback_work;
    wire [30:0] feedback_init_raw;
    wire [30:0] feedback_work_raw;


    wire [30:0] init_u;


    /*
     * Handshakes
     */

    wire init_fire;
    wire req_fire;


    /*
     * ZUC initialization constants
     */

    function [14:0] get_d;

        input integer index;

        begin

            case (index)

                0:  get_d = 15'h44D7;
                1:  get_d = 15'h26BC;
                2:  get_d = 15'h626B;
                3:  get_d = 15'h135E;

                4:  get_d = 15'h5789;
                5:  get_d = 15'h35E2;
                6:  get_d = 15'h7135;
                7:  get_d = 15'h09AF;

                8:  get_d = 15'h4D78;
                9:  get_d = 15'h2F13;
                10: get_d = 15'h6BC4;
                11: get_d = 15'h1AF1;

                12: get_d = 15'h5E26;
                13: get_d = 15'h3C4D;
                14: get_d = 15'h789A;
                15: get_d = 15'h47AC;

                default:
                    get_d = 15'd0;

            endcase

        end

    endfunction


    /*
     * Extract byte from reversed 32-bit Word order.
     *
     * Python:
     *
     * key_word = key[3-i]
     *
     * key_byte = key_word >> (8 * (3-j))
     */

    function [7:0] get_byte;

        input [127:0] value;
        input integer index;

        integer word_index;
        integer byte_index;

        reg [31:0] selected_word;

        begin

            word_index = index / 4;
            byte_index = index % 4;

            selected_word =
                value[word_index * 32 +: 32];

            get_byte =
                selected_word[24 - byte_index * 8 +: 8];

        end

    endfunction


    /*
     * ADDM modulo 2^31 - 1
     */

    function [30:0] addm31;

        input [30:0] a;
        input [30:0] b;

        reg [31:0] sum;
        reg [31:0] folded;

        begin

            sum = {1'b0, a} + {1'b0, b};

            folded =
                {1'b0, sum[30:0]} +
                sum[31];

            addm31 = folded[30:0];

        end

    endfunction


    /*
     * 31-bit rotate left
     */

    function [30:0] rotl31;

        input [30:0] value;
        input integer shift;

        begin

            rotl31 =
                ((value << shift) |
                 (value >> (31 - shift))) &
                31'h7FFFFFFF;

        end

    endfunction


    /*
     * Bit Reorganization
     */

    assign x0 = {
        s[15][30:15],
        s[14][15:0]
    };

    assign x1 = {
        s[11][15:0],
        s[9][30:15]
    };

    assign x2 = {
        s[7][15:0],
        s[5][30:15]
    };

    assign x3 = {
        s[2][15:0],
        s[0][30:15]
    };


    /*
     * F function
     */

    zuc_f u_zuc_f (
        .x0      (x0),
        .x1      (x1),
        .x2      (x2),

        .r1      (r1),
        .r2      (r2),

        .w       (w),

        .r1_next (r1_next),
        .r2_next (r2_next)
    );


    /*
     * LFSR Feedback
     *
     * s0 + ROT(s0,8)
     *    + ROT(s4,20)
     *    + ROT(s10,21)
     *    + ROT(s13,17)
     *    + ROT(s15,15)
     */

    assign feedback_base =
        addm31(
            addm31(
                addm31(
                    addm31(
                        addm31(
                            s[0],
                            rotl31(s[0], 8)
                        ),
                        rotl31(s[4], 20)
                    ),
                    rotl31(s[10], 21)
                ),
                rotl31(s[13], 17)
            ),
            rotl31(s[15], 15)
        );


    assign init_u =
        w[31:1];

    assign feedback_init_raw =
        addm31(feedback_base, init_u);

    assign feedback_work_raw =
        feedback_base;

    assign feedback_init =
    (feedback_init_raw == 31'd0)
        ? 31'h7FFFFFFF
        : feedback_init_raw;

    assign feedback_work =
        (feedback_work_raw == 31'd0)
            ? 31'h7FFFFFFF
            : feedback_work_raw;
    
    /*
     * Init Ready
     *
     * Supports reinitialization from ST_GEN
     * when no output word is pending.
     */

    assign o_init_ready =
        (state == ST_IDLE) ||
        ((state == ST_GEN) && !stream_valid_reg);


    assign init_fire =
        i_init && o_init_ready;


    /*
     * Stream request Ready
     */

    assign o_stream_req_ready =
        (state == ST_GEN) &&
        (!stream_valid_reg || i_stream_ready) &&
        !init_fire;


    assign req_fire =
        i_stream_req &&
        o_stream_req_ready;


    assign o_core_ready =
        (state == ST_GEN);


    assign o_stream =
        stream_reg;


    assign o_stream_vld =
        stream_valid_reg;


    assign o_busy =
        (state == ST_INIT) ||
        (state == ST_DISCARD);


    /*
     * LFSR and FSM sequential logic
     */

    integer i;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= ST_IDLE;

            init_cnt <= 6'd0;

            r1 <= 32'b0;
            r2 <= 32'b0;

            stream_reg <= 32'b0;
            stream_valid_reg <= 1'b0;

            for (i = 0; i < 16; i = i + 1)
                s[i] <= 31'b0;

        end
        else if (init_fire) begin

            /*
             * Load 16 LFSR stages.
             *
             * s[i] = {
             *   key_byte,
             *   D[i],
             *   iv_byte
             * }
             */

            for (i = 0; i < 16; i = i + 1) begin

                s[i] <= {
                    get_byte(i_key, i),
                    get_d(i),
                    get_byte(i_iv, i)
                };

            end

            r1 <= 32'b0;
            r2 <= 32'b0;

            init_cnt <= 6'd0;

            stream_reg <= 32'b0;
            stream_valid_reg <= 1'b0;

            state <= ST_INIT;

        end
        else begin

            case (state)

                /*
                 * IDLE
                 */

                ST_IDLE: begin
                end


                /*
                 * 32 initialization rounds
                 */

                ST_INIT: begin

                    r1 <= r1_next;
                    r2 <= r2_next;

                    for (i = 0; i < 15; i = i + 1)
                        s[i] <= s[i+1];

                    s[15] <= feedback_init;

                    if (init_cnt == 6'd31) begin

                        init_cnt <= 6'd0;
                        state <= ST_DISCARD;

                    end
                    else begin

                        init_cnt <= init_cnt + 6'd1;

                    end

                end


                /*
                 * Discard first working-mode word
                 */

                ST_DISCARD: begin

                    r1 <= r1_next;
                    r2 <= r2_next;

                    for (i = 0; i < 15; i = i + 1)
                        s[i] <= s[i+1];

                    s[15] <= feedback_work;

                    state <= ST_GEN;

                end


                /*
                 * Generate 32-bit Keystream
                 */

                ST_GEN: begin

                    /*
                     * Output consumption
                     */

                    if (stream_valid_reg && i_stream_ready)
                        stream_valid_reg <= 1'b0;


                    /*
                     * New request
                     */

                    if (req_fire) begin

                        /*
                         * z = X3 XOR W
                         */

                        stream_reg <=
                            x3 ^ w;

                        stream_valid_reg <= 1'b1;

                        /*
                         * Advance F
                         */

                        r1 <= r1_next;
                        r2 <= r2_next;

                        /*
                         * Advance LFSR
                         */

                        for (i = 0; i < 15; i = i + 1)
                            s[i] <= s[i+1];

                        s[15] <= feedback_work;

                    end

                end


                default: begin

                    state <= ST_IDLE;

                end

            endcase

        end

    end

endmodule