module zuc_mac (
    input  wire         clk,
    input  wire         rst_n,

    // Transaction
    input  wire         i_start,
    output wire         o_start_ready,

    // Message length in bytes
    input  wire [31:0]  i_msg_len,

    // 32-bit message input
    input  wire [31:0]  i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,

    // Valid bytes: 1..4
    input  wire [2:0]   i_valid_bytes,

    // 32-bit ZUC keystream
    input  wire [31:0]  i_z_word,
    input  wire         i_z_vld,
    output wire         o_z_ready,

    // MAC output
    output wire [31:0]  o_mac,
    output wire         o_mac_vld,
    input  wire         i_mac_ready,

    output wire         o_busy
);

    localparam ST_IDLE     = 3'd0;
    localparam ST_PREFETCH = 3'd1;
    localparam ST_DATA     = 3'd2;
    localparam ST_FINAL    = 3'd3;
    localparam ST_OUT      = 3'd4;

    reg [2:0] state;

    reg [31:0] msg_len_reg;
    reg [31:0] bytes_remaining;

    reg [31:0] mac_acc;

    reg [31:0] z_prev;

    reg [63:0] last_window;

    reg [31:0] mac_reg;
    reg        mac_valid_reg;

    wire start_fire;
    wire data_fire;
    wire z_fire;

    wire [31:0] masked_msg;
    wire [31:0] mac_delta;

    wire [63:0] current_window;

    wire [5:0] final_shift;

    wire [31:0] final_window;

    wire [63:0] shifted_window;

    /*
     * Transaction control
     */

    assign o_start_ready =
        (state == ST_IDLE);

    assign start_fire =
        i_start && o_start_ready;

    assign o_busy =
        (state != ST_IDLE);


    /*
     * Message input and Keystream must
     * advance together during ST_DATA.
     */

    assign o_data_ready =
        (state == ST_DATA) &&
        i_z_vld;

    assign o_z_ready =
        (state == ST_PREFETCH) ||
        ((state == ST_DATA) && i_data_vld) ||
        (state == ST_FINAL);

    assign data_fire =
        i_data_vld && o_data_ready;

    assign z_fire =
        i_z_vld && o_z_ready;


    /*
     * Mask invalid bytes.
     *
     * MSB-first.
     */

    assign masked_msg =
        (i_valid_bytes == 3'd4) ?
            i_data :

        (i_valid_bytes == 3'd3) ?
            (i_data & 32'hFFFFFF00) :

        (i_valid_bytes == 3'd2) ?
            (i_data & 32'hFFFF0000) :

        (i_valid_bytes == 3'd1) ?
            (i_data & 32'hFF000000) :

            32'b0;


    /*
     * Current 64-bit Keystream Window
     */

    assign current_window = {
        z_prev,
        i_z_word
    };


    /*
     * 32-bit parallel MAC calculation
     */

    zuc_mac_round32 u_mac_round (
        .i_msg       (masked_msg),
        .i_z0        (z_prev),
        .i_z1        (i_z_word),
        .o_mac_delta (mac_delta)
    );


    /*
     * Final bit position inside the
     * last 32-bit message word.
     *
     * 0,8,16,24.
     *
     * For aligned messages, final window
     * starts at the next keystream word.
     */

    assign final_shift =
        {msg_len_reg[1:0], 3'b000};


    assign shifted_window =
        last_window << final_shift;


    assign final_window =
        shifted_window[63:32];


    assign o_mac =
        mac_reg;

    assign o_mac_vld =
        mac_valid_reg;


    /*
     * Sequential control
     */

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= ST_IDLE;

            msg_len_reg <= 32'b0;
            bytes_remaining <= 32'b0;

            mac_acc <= 32'b0;

            z_prev <= 32'b0;

            last_window <= 64'b0;

            mac_reg <= 32'b0;
            mac_valid_reg <= 1'b0;

        end
        else begin

            case (state)

                /*
                 * Wait for transaction
                 */

                ST_IDLE: begin

                    mac_valid_reg <= 1'b0;

                    if (start_fire) begin

                        msg_len_reg <= i_msg_len;

                        bytes_remaining <= i_msg_len;

                        mac_acc <= 32'b0;

                        z_prev <= 32'b0;

                        last_window <= 64'b0;

                        state <= ST_PREFETCH;

                    end

                end


                /*
                 * Prefetch Z0
                 */

                ST_PREFETCH: begin

                    if (z_fire) begin

                        z_prev <= i_z_word;

                        if (msg_len_reg == 32'd0)
                            state <= ST_FINAL;
                        else
                            state <= ST_DATA;

                    end

                end


                /*
                 * Process one 32-bit MSG Word
                 * per cycle when both inputs valid.
                 */

                ST_DATA: begin

                    if (data_fire) begin

                        /*
                         * Accumulate MAC
                         */

                        mac_acc <=
                            mac_acc ^ mac_delta;


                        /*
                         * Save current window.
                         */

                        last_window <= current_window;


                        /*
                         * Advance rolling Z window.
                         */

                        z_prev <= i_z_word;


                        /*
                         * Count message bytes.
                         */

                        bytes_remaining <=
                            bytes_remaining - i_valid_bytes;


                        /*
                         * Last message beat
                         */

                        if (bytes_remaining <= i_valid_bytes)
                            state <= ST_FINAL;

                    end

                end


                /*
                 * Fetch final OTP Z word.
                 *
                 * At this point:
                 *
                 * z_prev = Z[N]
                 *
                 * For aligned messages:
                 *   GET_WORD(Z,LENGTH) = Z[N]
                 *
                 * For partial messages:
                 *   GET_WORD uses last_window.
                 *
                 * Final OTP = Z[N+1].
                 */

                ST_FINAL: begin

                    if (z_fire) begin

                        if (msg_len_reg == 32'd0) begin

                            /*
                             * Zero-length message:
                             *
                             * T = Z0 XOR Z1
                             */

                            mac_reg <=
                                mac_acc ^
                                z_prev ^
                                i_z_word;

                        end
                        else if (msg_len_reg[1:0] == 2'd0) begin

                            /*
                             * Word-aligned length.
                             */

                            mac_reg <=
                                mac_acc ^
                                z_prev ^
                                i_z_word;

                        end
                        else begin

                            /*
                             * Partial final word.
                             */

                            mac_reg <=
                                mac_acc ^
                                final_window ^
                                i_z_word;

                        end

                        mac_valid_reg <= 1'b1;

                        state <= ST_OUT;

                    end

                end


                /*
                 * Hold MAC until consumed.
                 */

                ST_OUT: begin

                    if (mac_valid_reg &&
                        i_mac_ready) begin

                        mac_valid_reg <= 1'b0;

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