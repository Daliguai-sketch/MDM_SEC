module zuc_int (
    input  wire         clk,
    input  wire         rst_n,

    // Transaction start
    input  wire         i_start,
    output wire         o_start_ready,

    input  wire [127:0] i_key,

    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    // Message length in bytes
    input  wire [31:0]  i_msg_len,

    // Message input
    input  wire [31:0]  i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,

    input  wire [2:0]   i_valid_bytes,

    // MAC output
    output wire [31:0]  o_mac,
    output wire         o_mac_vld,
    input  wire         i_mac_ready,

    output wire         o_busy
);

    localparam ST_IDLE       = 3'd0;
    localparam ST_INIT       = 3'd1;
    localparam ST_WAIT_INIT  = 3'd2;
    localparam ST_MAC_START  = 3'd3;
    localparam ST_RUN        = 3'd4;

    reg [2:0] state;


    /*
     * Transaction registers
     */

    reg [127:0] key_reg;
    reg [127:0] iv_reg;

    reg [31:0] msg_len_reg;


    /*
     * Keystream request counter
     */

    reg [33:0] req_remaining;

    wire [33:0] required_words;

    wire req_fire;


    /*
     * ZUC Core
     */

    reg zuc_init;

    wire zuc_init_ready;
    wire zuc_core_ready;

    wire zuc_req;
    wire zuc_req_ready;

    wire [31:0] zuc_word;
    wire        zuc_word_vld;
    wire        zuc_word_ready;

    wire zuc_busy;


    /*
     * MAC Engine
     */

    reg mac_start;

    wire mac_start_ready;
    wire mac_busy;


    /*
     * INT IV construction
     *
     * Matches current Python implementation.
     */

    wire [31:0] fresh;

    wire [31:0] iv0;
    wire [31:0] iv1;
    wire [31:0] iv2;
    wire [31:0] iv3;


    assign fresh = {
        i_bearer,
        27'b0
    };

    assign iv0 =
        fresh ^ {31'b0, i_direction};

    assign iv1 =
        i_count ^ {31'b0, i_direction};

    assign iv2 = fresh;

    assign iv3 = i_count;


    /*
     * ceil(msg_len / 4) + 2
     *
     * 34-bit arithmetic prevents overflow.
     */

    assign required_words =
        ({2'b00, i_msg_len} + 34'd3) / 34'd4
        + 34'd2;


    /*
     * Top-level status
     */

    assign o_start_ready =
        (state == ST_IDLE);

    assign o_busy =
        (state != ST_IDLE);


    /*
     * Generate exactly required_words
     * Keystream requests.
     */

    assign zuc_req =
        (state == ST_RUN) &&
        (req_remaining != 34'd0);


    assign req_fire =
        zuc_req &&
        zuc_req_ready;


    /*
     * Independent ZUC Core
     */

    zuc_core u_zuc_int_core (
        .clk                (clk),
        .rst_n              (rst_n),

        .i_init             (zuc_init),
        .o_init_ready       (zuc_init_ready),

        .i_key              (key_reg),
        .i_iv               (iv_reg),

        .o_core_ready       (zuc_core_ready),

        .i_stream_req       (zuc_req),
        .o_stream_req_ready (zuc_req_ready),

        .o_stream           (zuc_word),
        .o_stream_vld       (zuc_word_vld),
        .i_stream_ready     (zuc_word_ready),

        .o_busy             (zuc_busy)
    );


    /*
     * ZUC MAC Engine
     */

    zuc_mac u_zuc_mac (
        .clk            (clk),
        .rst_n          (rst_n),

        .i_start        (mac_start),
        .o_start_ready  (mac_start_ready),

        .i_msg_len      (msg_len_reg),

        .i_data         (i_data),
        .i_data_vld     (i_data_vld),
        .o_data_ready   (o_data_ready),

        .i_valid_bytes  (i_valid_bytes),

        .i_z_word       (zuc_word),
        .i_z_vld        (zuc_word_vld),
        .o_z_ready      (zuc_word_ready),

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
            iv_reg <= 128'b0;

            msg_len_reg <= 32'b0;

            req_remaining <= 34'd0;

            zuc_init <= 1'b0;
            mac_start <= 1'b0;

        end
        else begin

            zuc_init <= 1'b0;
            mac_start <= 1'b0;


            case (state)

                /*
                 * New MAC transaction
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

                        req_remaining <= required_words;

                        state <= ST_INIT;

                    end

                end


                /*
                 * Initialize ZUC Core
                 */

                ST_INIT: begin

                    if (zuc_init_ready) begin

                        zuc_init <= 1'b1;

                        state <= ST_WAIT_INIT;

                    end

                end


                /*
                 * Wait for 32 initialization
                 * rounds plus discard.
                 */

                ST_WAIT_INIT: begin

                    if (zuc_core_ready)
                        state <= ST_MAC_START;

                end


                /*
                 * Start MAC Engine
                 */

                ST_MAC_START: begin

                    if (mac_start_ready) begin

                        mac_start <= 1'b1;

                        state <= ST_RUN;

                    end

                end


                /*
                 * Stream processing
                 */

                ST_RUN: begin

                    /*
                     * Request counter
                     */

                    if (req_fire) begin

                        req_remaining <=
                            req_remaining - 34'd1;

                    end


                    /*
                     * Transaction finishes only
                     * after MAC output handshake.
                     */

                    if (o_mac_vld &&
                        i_mac_ready) begin

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