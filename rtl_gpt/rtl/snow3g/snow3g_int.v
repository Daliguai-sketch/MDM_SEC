module snow3g_int (
    input  wire         clk,
    input  wire         rst_n,

    // MAC transaction
    input  wire         i_start,
    output wire         o_start_ready,

    input  wire [127:0] i_key,

    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    // Message length in bytes
    input  wire [31:0]  i_msg_len,

    // 64-bit message input
    input  wire [63:0]  i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,
    input  wire [3:0]   i_valid_bytes,

    // MAC output
    output wire [31:0]  o_mac,
    output wire         o_mac_vld,
    input  wire         i_mac_ready,

    output wire         o_busy
);

    /*
     * FSM states
     */

    localparam ST_IDLE       = 3'd0;
    localparam ST_INIT       = 3'd1;
    localparam ST_WAIT_INIT  = 3'd2;
    localparam ST_STREAM     = 3'd3;
    localparam ST_MAC_START  = 3'd4;
    localparam ST_MAC_RUN    = 3'd5;

    reg [2:0] state;


    /*
     * Transaction registers
     */

    reg [127:0] key_reg;
    reg [127:0] iv_reg;

    reg [31:0] msg_len_reg;


    /*
     * MAC parameters
     */

    reg [63:0] p_reg;
    reg [63:0] q_reg;
    reg [31:0] otp_reg;


    /*
     * Independent request/output counters
     */

    reg [2:0] req_count;
    reg [2:0] recv_count;


    /*
     * SNOW3G Core signals
     */

    reg  snow_init;

    wire snow_init_ready;
    wire snow_ready;

    wire snow_req;
    wire snow_req_ready;

    wire [31:0] snow_stream;
    wire        snow_stream_vld;
    wire        snow_stream_ready;

    wire snow_busy;

    wire req_fire;
    wire stream_fire;


    /*
     * MAC Core signals
     */

    reg  mac_start;

    wire mac_start_ready;
    wire mac_busy;


    /*
     * IV construction
     */

    wire [31:0] fresh;

    wire [31:0] iv0;
    wire [31:0] iv1;
    wire [31:0] iv2;
    wire [31:0] iv3;


    /*
     * Python:
     *
     * fresh = bearer << 27
     *
     * IV0 = fresh XOR (direction << 15)
     * IV1 = count XOR direction
     * IV2 = fresh
     * IV3 = count
     */

    assign fresh = {
        i_bearer,
        27'b0
    };

    assign iv0 =
        fresh ^ {16'b0, i_direction, 15'b0};

    assign iv1 =
        i_count ^ {31'b0, i_direction};

    assign iv2 = fresh;

    assign iv3 = i_count;


    /*
     * Top-level control
     */

    assign o_start_ready =
        (state == ST_IDLE);

    assign o_busy =
        (state != ST_IDLE);


    /*
     * SNOW3G Word request
     *
     * Exactly five requests per MAC transaction.
     */

    assign snow_req =
        (state == ST_STREAM) &&
        (req_count < 3'd5);


    /*
     * Core output is always ready while
     * collecting the five Keystream Words.
     */

    assign snow_stream_ready =
        (state == ST_STREAM) &&
        (recv_count < 3'd5);


    /*
     * Request handshake
     */

    assign req_fire =
        snow_req &&
        snow_req_ready;


    /*
     * Output handshake
     */

    assign stream_fire =
        snow_stream_vld &&
        snow_stream_ready;


    /*
     * Independent SNOW3G INT Core
     */

    snow3g_core u_snow3g_int_core (
        .clk                (clk),
        .rst_n              (rst_n),

        .i_init             (snow_init),
        .o_init_ready       (snow_init_ready),

        .i_key              (key_reg),
        .i_iv               (iv_reg),

        .o_core_ready       (snow_ready),

        .i_stream_req       (snow_req),
        .o_stream_req_ready (snow_req_ready),

        .o_stream           (snow_stream),
        .o_stream_vld       (snow_stream_vld),
        .i_stream_ready     (snow_stream_ready),

        .o_busy             (snow_busy)
    );


    /*
     * SNOW3G MAC Core
     */

    snow3g_mac u_snow3g_mac (
        .clk            (clk),
        .rst_n          (rst_n),

        .i_start        (mac_start),
        .o_start_ready  (mac_start_ready),

        .i_p            (p_reg),
        .i_q            (q_reg),
        .i_otp          (otp_reg),

        .i_msg_len      (msg_len_reg),

        .i_data         (i_data),
        .i_data_vld     (i_data_vld),
        .o_data_ready   (o_data_ready),

        .i_valid_bytes  (i_valid_bytes),

        .o_mac          (o_mac),
        .o_mac_vld      (o_mac_vld),
        .i_mac_ready    (i_mac_ready),

        .o_busy         (mac_busy)
    );


    /*
     * Control FSM
     */

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            state <= ST_IDLE;

            key_reg <= 128'b0;
            iv_reg  <= 128'b0;

            msg_len_reg <= 32'b0;

            p_reg   <= 64'b0;
            q_reg   <= 64'b0;
            otp_reg <= 32'b0;

            req_count  <= 3'd0;
            recv_count <= 3'd0;

            snow_init <= 1'b0;
            mac_start <= 1'b0;

        end
        else begin

            /*
             * Default one-cycle control pulses
             */

            snow_init <= 1'b0;
            mac_start <= 1'b0;


            case (state)

                /*
                 * Wait for new MAC transaction
                 */

                ST_IDLE: begin

                    if (i_start && o_start_ready) begin

                        key_reg <= i_key;

                        iv_reg <= {
                            iv0,
                            iv1,
                            iv2,
                            iv3
                        };

                        msg_len_reg <= i_msg_len;

                        p_reg <= 64'b0;
                        q_reg <= 64'b0;
                        otp_reg <= 32'b0;

                        req_count  <= 3'd0;
                        recv_count <= 3'd0;

                        state <= ST_INIT;

                    end

                end


                /*
                 * Initialize SNOW3G Core
                 */

                ST_INIT: begin

                    if (snow_init_ready) begin

                        snow_init <= 1'b1;

                        state <= ST_WAIT_INIT;

                    end

                end


                /*
                 * Wait for 32 initialization cycles
                 * plus one discard cycle
                 */

                ST_WAIT_INIT: begin

                    if (snow_ready) begin

                        state <= ST_STREAM;

                    end

                end


                /*
                 * Generate exactly five
                 * 32-bit Keystream Words
                 */

                ST_STREAM: begin

                    /*
                     * Request counter
                     */

                    if (req_fire) begin

                        req_count <=
                            req_count + 3'd1;

                    end


                    /*
                     * Output counter
                     */

                    if (stream_fire) begin

                        case (recv_count)

                            3'd0: begin

                                p_reg[63:32] <=
                                    snow_stream;

                            end


                            3'd1: begin

                                p_reg[31:0] <=
                                    snow_stream;

                            end


                            3'd2: begin

                                q_reg[63:32] <=
                                    snow_stream;

                            end


                            3'd3: begin

                                q_reg[31:0] <=
                                    snow_stream;

                            end


                            3'd4: begin

                                otp_reg <=
                                    snow_stream;

                            end


                            default: begin
                            end

                        endcase


                        recv_count <=
                            recv_count + 3'd1;


                        /*
                         * Fifth Word received.
                         */

                        if (recv_count == 3'd4) begin

                            state <= ST_MAC_START;

                        end

                    end

                end


                /*
                 * Start MAC calculation
                 */

                ST_MAC_START: begin

                    if (mac_start_ready) begin

                        mac_start <= 1'b1;

                        state <= ST_MAC_RUN;

                    end

                end


                /*
                 * Wait for final MAC output
                 */

                ST_MAC_RUN: begin

                    if (o_mac_vld && i_mac_ready) begin

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