module sec_process_ctrl (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         i_start,
    output wire         o_start_ready,

    input  wire [2:0]   i_mode,
    input  wire         i_int_move,

    input  wire [1:0]   i_enc_alg_sel,
    input  wire [1:0]   i_int_alg_sel,

    input  wire [127:0] i_enc_key,
    input  wire [127:0] i_int_key,

    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    input  wire [31:0]  i_int_only_bytes,
    input  wire [31:0]  i_enc_bytes,

    // INT Only Input
    input  wire [127:0] i_int_only_data,
    input  wire         i_int_only_data_vld,
    output wire         o_int_only_data_ready,
    input  wire         i_int_only_data_last,
    input  wire [4:0]   i_int_only_valid_bytes,

    // ENC Input
    input  wire [127:0] i_enc_data,
    input  wire         i_enc_data_vld,
    output wire         o_enc_data_ready,
    input  wire         i_enc_data_last,
    input  wire [4:0]   i_enc_valid_bytes,

    // Cipher Output
    output wire [127:0] o_cipher_data,
    output wire         o_cipher_data_vld,
    input  wire         i_cipher_data_ready,
    output wire         o_cipher_data_last,
    output wire [4:0]   o_cipher_valid_bytes,

    // INT Move Output
    output wire [127:0] o_int_move_data,
    output wire         o_int_move_data_vld,
    input  wire         i_int_move_data_ready,
    output wire         o_int_move_data_last,
    output wire [4:0]   o_int_move_valid_bytes,

    // MAC Output
    output wire [31:0]  o_mac,
    output wire         o_mac_vld,
    input  wire         i_mac_ready,

    output wire         o_busy,
    output reg          o_done
);

    // =====================================================
    // Mode
    // =====================================================

    localparam MODE_ENC_ONLY = 3'd0;
    localparam MODE_INT_ONLY = 3'd1;
    localparam MODE_INT2ENC  = 3'd2;
    localparam MODE_ENC2INT  = 3'd3;
    localparam MODE_PARALLEL = 3'd4;

    // =====================================================
    // Input State
    // =====================================================

    localparam INPUT_INT_ONLY = 2'd0;
    localparam INPUT_ENC      = 2'd1;
    localparam INPUT_DONE     = 2'd2;

    reg [1:0] input_state;

    // =====================================================
    // Transaction Registers
    // =====================================================

    reg active;

    reg [2:0] mode_reg;
    reg       int_move_reg;

    reg [1:0] enc_alg_reg;
    reg [1:0] int_alg_reg;

    reg [127:0] enc_key_reg;
    reg [127:0] int_key_reg;

    reg [31:0] count_reg;
    reg [4:0]  bearer_reg;
    reg        direction_reg;

    reg [31:0] int_only_bytes_reg;
    reg [31:0] enc_bytes_reg;

    reg [31:0] enc_total_bytes;
    reg [31:0] int_total_bytes;

    reg [31:0] int_only_recv_bytes;
    reg [31:0] enc_recv_bytes;

    wire use_enc;
    wire use_int;

    assign use_enc = (mode_reg != MODE_INT_ONLY);
    assign use_int = (mode_reg != MODE_ENC_ONLY);

    assign o_start_ready = !active;
    assign o_busy = active;

    wire process_start;

    assign process_start =
        i_start &&
        o_start_ready &&
        (i_mode <= MODE_PARALLEL);

    // =====================================================
    // Byte Functions
    // =====================================================

    function [127:0] mask128;

        input [127:0] data;
        input [4:0] bytes;

        integer k;

        begin

            mask128 = 128'b0;

            for (k = 0; k < 16; k = k + 1) begin

                if (k < bytes)
                    mask128[127-k*8 -: 8] =
                        data[127-k*8 -: 8];

            end

        end

    endfunction

    function [255:0] append_data;

        input [255:0] old_data;
        input [5:0] old_bytes;

        input [127:0] new_data;
        input [4:0] new_bytes;

        reg [255:0] shifted;

        begin

            shifted =
                {mask128(new_data, new_bytes),128'b0}
                >> (old_bytes * 8);

            append_data = old_data | shifted;

        end

    endfunction

    // =====================================================
    // Core Start
    // =====================================================

    reg enc_start_pending;
    reg int_start_pending;

    reg enc_started;
    reg int_started;

    reg enc_done_flag;
    reg int_done_flag;

    wire enc_start_ready;
    wire int_start_ready;

    wire enc_start_fire;
    wire int_start_fire;

    wire enc_done;
    wire int_done;

    assign enc_start_fire =
        enc_start_pending && enc_start_ready;

    assign int_start_fire =
        int_start_pending && int_start_ready;

    // =====================================================
    // INT Only Input Stage
    // =====================================================

    reg [127:0] int_only_stage_data;
    reg [4:0]   int_only_stage_bytes;
    reg         int_only_stage_valid;

    wire int_only_input_fire;

    assign o_int_only_data_ready =
        active &&
        int_started &&
        (input_state == INPUT_INT_ONLY) &&
        !int_only_stage_valid;

    assign int_only_input_fire =
        i_int_only_data_vld &&
        o_int_only_data_ready;

    // =====================================================
    // Original ENC Buffer
    // =====================================================

    reg [127:0] enc_buf_data;
    reg [4:0]   enc_buf_bytes;

    reg enc_buf_valid;

    reg enc_buf_to_enc;
    reg enc_buf_to_int;

    wire enc_input_fire;

    assign o_enc_data_ready =
        active &&
        (input_state == INPUT_ENC) &&
        !enc_buf_valid &&
        (
            enc_started ||
            ((mode_reg == MODE_INT_ONLY) && int_started)
        );

    assign enc_input_fire =
        i_enc_data_vld &&
        o_enc_data_ready;

    // =====================================================
    // Cipher Buffer
    // =====================================================

    reg [127:0] cipher_buf_data;
    reg [4:0]   cipher_buf_bytes;
    reg         cipher_buf_last;

    reg cipher_buf_valid;

    reg cipher_output_pending;
    reg cipher_int_pending;

    assign o_cipher_data =
        cipher_buf_data;

    assign o_cipher_data_vld =
        cipher_buf_valid &&
        cipher_output_pending;

    assign o_cipher_data_last =
        cipher_buf_last;

    assign o_cipher_valid_bytes =
        cipher_buf_bytes;

    wire cipher_output_fire;

    assign cipher_output_fire =
        o_cipher_data_vld &&
        i_cipher_data_ready;

    // =====================================================
    // ENC Alignment
    // =====================================================

    reg [255:0] enc_align_data;
    reg [5:0]   enc_align_count;

    reg [31:0] enc_align_received;
    reg [31:0] enc_align_sent;

    reg mac_appended;

    wire enc_take_original;
    wire enc_take_mac;

    wire [127:0] enc_core_input_data;
    wire         enc_core_input_valid;
    wire         enc_core_input_ready;
    wire         enc_core_input_last;
    wire [4:0]   enc_core_input_bytes;

    wire enc_core_input_fire;

    assign enc_take_original =
        active &&
        enc_started &&
        enc_buf_valid &&
        enc_buf_to_enc &&
        (enc_align_count < 6'd16);

    // =====================================================
    // MAC Buffer
    // =====================================================

    reg [31:0] mac_out_reg;
    reg        mac_out_valid;

    reg [31:0] mac_append_reg;
    reg        mac_captured;

    wire [31:0] int_core_mac;
    wire        int_core_mac_valid;
    wire        int_core_mac_ready;

    wire mac_core_fire;
    wire mac_output_fire;

    assign int_core_mac_ready =
        active &&
        !mac_out_valid;

    assign mac_core_fire =
        int_core_mac_valid &&
        int_core_mac_ready;

    assign o_mac = mac_out_reg;
    assign o_mac_vld = mac_out_valid;

    assign mac_output_fire =
        o_mac_vld && i_mac_ready;

    assign enc_take_mac =
        active &&
        enc_started &&
        (mode_reg == MODE_INT2ENC) &&
        (enc_align_received == enc_bytes_reg) &&
        !enc_buf_valid &&
        mac_captured &&
        !mac_appended &&
        (enc_align_count < 6'd16);

    // =====================================================
    // ENC Core Input
    //
    // Last is determined from total byte count.
    // =====================================================

    wire [31:0] enc_bytes_remaining;

    assign enc_bytes_remaining =
        enc_total_bytes - enc_align_sent;

    assign enc_core_input_data =
        enc_align_data[255:128];

    assign enc_core_input_bytes =
        (enc_bytes_remaining >= 32'd16)
        ? 5'd16
        : enc_bytes_remaining[4:0];

    assign enc_core_input_last =
        (enc_bytes_remaining <= 32'd16);

    assign enc_core_input_valid =
        active &&
        enc_started &&
        (enc_bytes_remaining != 0) &&
        (
            (enc_align_count >= 6'd16) ||
            (
                (enc_align_received == enc_total_bytes) &&
                (enc_align_count != 0)
            )
        );

    assign enc_core_input_fire =
        enc_core_input_valid &&
        enc_core_input_ready;

    // =====================================================
    // INT Alignment
    // =====================================================

    reg [255:0] int_align_data;
    reg [5:0]   int_align_count;

    reg [31:0] int_align_received;
    reg [31:0] int_align_sent;

    wire int_take_int_only;
    wire int_take_original;
    wire int_take_cipher;

    assign int_take_int_only =
        active &&
        int_started &&
        int_only_stage_valid &&
        (int_align_count < 6'd16);

    assign int_take_original =
        active &&
        int_started &&
        (mode_reg != MODE_ENC2INT) &&
        (mode_reg != MODE_ENC_ONLY) &&
        (input_state != INPUT_INT_ONLY) &&
        !int_only_stage_valid &&
        enc_buf_valid &&
        enc_buf_to_int &&
        (int_align_count < 6'd16);

    assign int_take_cipher =
        active &&
        int_started &&
        (mode_reg == MODE_ENC2INT) &&
        (input_state != INPUT_INT_ONLY) &&
        !int_only_stage_valid &&
        cipher_buf_valid &&
        cipher_int_pending &&
        (int_align_count < 6'd16);

    // =====================================================
    // INT Output Register
    // =====================================================

    reg [127:0] int_out_data;
    reg [4:0]   int_out_bytes;
    reg         int_out_last;

    reg int_out_valid;

    reg int_core_pending;
    reg int_move_pending;

    wire int_out_free;

    assign int_out_free = !int_out_valid;

    wire [31:0] int_bytes_remaining;

    assign int_bytes_remaining =
        int_total_bytes - int_align_sent;

    wire int_align_output_load;

    assign int_align_output_load =
        active &&
        int_started &&
        use_int &&
        int_out_free &&
        (int_bytes_remaining != 0) &&
        (
            (int_align_count >= 6'd16) ||
            (
                (int_align_received == int_total_bytes) &&
                (int_align_count != 0)
            )
        );

    // =====================================================
    // INT Core Interface
    // =====================================================

    wire int_core_input_ready;

    wire int_core_fire;

    assign int_core_fire =
        int_out_valid &&
        int_core_pending &&
        int_core_input_ready;

    // =====================================================
    // INT Move Output
    // =====================================================

    assign o_int_move_data =
        int_out_data;

    assign o_int_move_data_vld =
        int_out_valid &&
        int_move_pending;

    assign o_int_move_data_last =
        int_out_last;

    assign o_int_move_valid_bytes =
        int_out_bytes;

    wire int_move_fire;

    assign int_move_fire =
        o_int_move_data_vld &&
        i_int_move_data_ready;

    // =====================================================
    // ENC Output Interface
    // =====================================================

    wire [127:0] enc_core_output_data;
    wire         enc_core_output_valid;
    wire         enc_core_output_ready;
    wire         enc_core_output_last;
    wire [4:0]   enc_core_output_bytes;

    wire enc_core_output_fire;

    assign enc_core_output_ready =
        active &&
        !cipher_buf_valid;

    assign enc_core_output_fire =
        enc_core_output_valid &&
        enc_core_output_ready;

    // =====================================================
    // SEC ENC TOP
    // =====================================================

    sec_enc_top u_sec_enc_top (

        .clk               (clk),
        .rst_n             (rst_n),

        .i_start           (enc_start_pending),
        .o_start_ready     (enc_start_ready),

        .i_alg_sel         (enc_alg_reg),
        .i_key             (enc_key_reg),

        .i_count           (count_reg),
        .i_bearer          (bearer_reg),
        .i_direction       (direction_reg),

        .i_packet_bytes    (enc_total_bytes),

        .i_data            (enc_core_input_data),
        .i_data_vld        (enc_core_input_valid),
        .o_data_ready      (enc_core_input_ready),
        .i_data_last       (enc_core_input_last),
        .i_valid_bytes     (enc_core_input_bytes),

        .o_data            (enc_core_output_data),
        .o_data_vld        (enc_core_output_valid),
        .i_data_ready      (enc_core_output_ready),
        .o_data_last       (enc_core_output_last),
        .o_valid_bytes     (enc_core_output_bytes),

        .o_busy            (),
        .o_done            (enc_done)

    );

    // =====================================================
    // SEC INT TOP
    // =====================================================

    sec_int_top u_sec_int_top (

        .clk               (clk),
        .rst_n             (rst_n),

        .i_start           (int_start_pending),
        .o_start_ready     (int_start_ready),

        .i_alg_sel         (int_alg_reg),
        .i_key             (int_key_reg),

        .i_count           (count_reg),
        .i_bearer          (bearer_reg),
        .i_direction       (direction_reg),

        .i_msg_len         (int_total_bytes),

        .i_data            (int_out_data),

        .i_data_vld        (
            int_out_valid &&
            int_core_pending
        ),

        .o_data_ready      (int_core_input_ready),

        .i_data_last       (int_out_last),
        .i_valid_bytes     (int_out_bytes),

        .o_mac             (int_core_mac),
        .o_mac_vld         (int_core_mac_valid),
        .i_mac_ready       (int_core_mac_ready),

        .o_busy            (),
        .o_done            (int_done)

    );

    // =====================================================
    // Main Transaction Control
    // =====================================================

    wire process_complete;

    assign process_complete =
        active &&
        (!use_enc || enc_done_flag) &&
        (!use_int || int_done_flag) &&
        !cipher_buf_valid &&
        !int_out_valid &&
        !mac_out_valid;

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            active <= 1'b0;

            mode_reg <= MODE_ENC_ONLY;
            int_move_reg <= 1'b0;

            enc_alg_reg <= 2'b0;
            int_alg_reg <= 2'b0;

            enc_key_reg <= 128'b0;
            int_key_reg <= 128'b0;

            count_reg <= 32'b0;
            bearer_reg <= 5'b0;
            direction_reg <= 1'b0;

            int_only_bytes_reg <= 32'b0;
            enc_bytes_reg <= 32'b0;

            enc_total_bytes <= 32'b0;
            int_total_bytes <= 32'b0;

            enc_start_pending <= 1'b0;
            int_start_pending <= 1'b0;

            enc_started <= 1'b0;
            int_started <= 1'b0;

            enc_done_flag <= 1'b0;
            int_done_flag <= 1'b0;

            o_done <= 1'b0;

        end
        else begin

            o_done <= 1'b0;

            if (process_start) begin

                active <= 1'b1;

                mode_reg <= i_mode;
                int_move_reg <= i_int_move;

                enc_alg_reg <= i_enc_alg_sel;
                int_alg_reg <= i_int_alg_sel;

                enc_key_reg <= i_enc_key;
                int_key_reg <= i_int_key;

                count_reg <= i_count;
                bearer_reg <= i_bearer;
                direction_reg <= i_direction;

                int_only_bytes_reg <= i_int_only_bytes;
                enc_bytes_reg <= i_enc_bytes;

                case (i_mode)

                    MODE_ENC_ONLY: begin

                        enc_total_bytes <= i_enc_bytes;
                        int_total_bytes <= 32'd0;

                    end

                    MODE_INT_ONLY: begin

                        enc_total_bytes <= 32'd0;

                        int_total_bytes <=
                            i_int_only_bytes +
                            i_enc_bytes;

                    end

                    MODE_INT2ENC: begin

                        enc_total_bytes <=
                            i_enc_bytes + 32'd4;

                        int_total_bytes <=
                            i_int_only_bytes +
                            i_enc_bytes;

                    end

                    default: begin

                        enc_total_bytes <= i_enc_bytes;

                        int_total_bytes <=
                            i_int_only_bytes +
                            i_enc_bytes;

                    end

                endcase

                enc_start_pending <=
                    (i_mode != MODE_INT_ONLY);

                int_start_pending <=
                    (i_mode != MODE_ENC_ONLY);

                enc_started <= 1'b0;
                int_started <= 1'b0;

                enc_done_flag <= 1'b0;
                int_done_flag <= 1'b0;

            end
            else begin

                if (enc_start_fire) begin

                    enc_start_pending <= 1'b0;
                    enc_started <= 1'b1;

                end

                if (int_start_fire) begin

                    int_start_pending <= 1'b0;
                    int_started <= 1'b1;

                end

                if (enc_done)
                    enc_done_flag <= 1'b1;

                if (int_done)
                    int_done_flag <= 1'b1;

                if (process_complete) begin

                    active <= 1'b0;
                    o_done <= 1'b1;

                end

            end

        end

    end

    // =====================================================
    // Input Sequence Control
    //
    // INT Only Data must arrive before ENC Data.
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            input_state <= INPUT_DONE;

            int_only_recv_bytes <= 32'b0;
            enc_recv_bytes <= 32'b0;

        end
        else if (process_start) begin

            int_only_recv_bytes <= 32'b0;
            enc_recv_bytes <= 32'b0;

            if (
                (i_mode != MODE_ENC_ONLY) &&
                (i_int_only_bytes != 0)
            )
                input_state <= INPUT_INT_ONLY;

            else if (i_enc_bytes != 0)
                input_state <= INPUT_ENC;

            else
                input_state <= INPUT_DONE;

        end
        else begin

            if (int_only_input_fire) begin

                int_only_recv_bytes <=
                    int_only_recv_bytes +
                    i_int_only_valid_bytes;

                if (
                    int_only_recv_bytes +
                    i_int_only_valid_bytes >=
                    int_only_bytes_reg
                ) begin

                    if (enc_bytes_reg != 0)
                        input_state <= INPUT_ENC;
                    else
                        input_state <= INPUT_DONE;

                end

            end

            if (enc_input_fire) begin

                enc_recv_bytes <=
                    enc_recv_bytes +
                    i_enc_valid_bytes;

                if (
                    enc_recv_bytes +
                    i_enc_valid_bytes >=
                    enc_bytes_reg
                )
                    input_state <= INPUT_DONE;

            end

        end

    end

    // =====================================================
    // INT Only Stage
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            int_only_stage_data <= 128'b0;
            int_only_stage_bytes <= 5'b0;
            int_only_stage_valid <= 1'b0;

        end
        else if (process_start) begin

            int_only_stage_valid <= 1'b0;

        end
        else begin

            if (int_only_input_fire) begin

                int_only_stage_data <=
                    mask128(
                        i_int_only_data,
                        i_int_only_valid_bytes
                    );

                int_only_stage_bytes <=
                    i_int_only_valid_bytes;

                int_only_stage_valid <= 1'b1;

            end

            if (int_take_int_only)
                int_only_stage_valid <= 1'b0;

        end

    end

    // =====================================================
    // Original ENC Buffer
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            enc_buf_data <= 128'b0;
            enc_buf_bytes <= 5'b0;

            enc_buf_valid <= 1'b0;

            enc_buf_to_enc <= 1'b0;
            enc_buf_to_int <= 1'b0;

        end
        else if (process_start) begin

            enc_buf_valid <= 1'b0;

            enc_buf_to_enc <= 1'b0;
            enc_buf_to_int <= 1'b0;

        end
        else begin

            if (enc_input_fire) begin

                enc_buf_data <=
                    mask128(
                        i_enc_data,
                        i_enc_valid_bytes
                    );

                enc_buf_bytes <=
                    i_enc_valid_bytes;

                enc_buf_valid <= 1'b1;

                enc_buf_to_enc <=
                    (mode_reg != MODE_INT_ONLY);

                enc_buf_to_int <=
                    (
                        mode_reg == MODE_INT_ONLY ||
                        mode_reg == MODE_INT2ENC  ||
                        mode_reg == MODE_PARALLEL
                    );

            end

            if (enc_take_original)
                enc_buf_to_enc <= 1'b0;

            if (int_take_original)
                enc_buf_to_int <= 1'b0;

            if (
                enc_buf_valid &&
                (!enc_buf_to_enc || enc_take_original) &&
                (!enc_buf_to_int || int_take_original)
            )
                enc_buf_valid <= 1'b0;

        end

    end

    // =====================================================
    // MAC Buffer
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            mac_out_reg <= 32'b0;
            mac_out_valid <= 1'b0;

            mac_append_reg <= 32'b0;
            mac_captured <= 1'b0;

        end
        else if (process_start) begin

            mac_out_valid <= 1'b0;

            mac_append_reg <= 32'b0;
            mac_captured <= 1'b0;

        end
        else begin

            if (mac_core_fire) begin

                mac_out_reg <= int_core_mac;
                mac_out_valid <= 1'b1;

                if (mode_reg == MODE_INT2ENC) begin

                    mac_append_reg <= int_core_mac;
                    mac_captured <= 1'b1;

                end

            end

            if (mac_output_fire)
                mac_out_valid <= 1'b0;

        end

    end

    // =====================================================
    // ENC Alignment
    //
    // Original Data + optional MAC
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            enc_align_data <= 256'b0;
            enc_align_count <= 6'b0;

            enc_align_received <= 32'b0;
            enc_align_sent <= 32'b0;

            mac_appended <= 1'b0;

        end
        else if (process_start) begin

            enc_align_data <= 256'b0;
            enc_align_count <= 6'b0;

            enc_align_received <= 32'b0;
            enc_align_sent <= 32'b0;

            mac_appended <= 1'b0;

        end
        else begin

            if (enc_take_original) begin

                enc_align_data <=
                    append_data(
                        enc_align_data,
                        enc_align_count,
                        enc_buf_data,
                        enc_buf_bytes
                    );

                enc_align_count <=
                    enc_align_count +
                    enc_buf_bytes;

                enc_align_received <=
                    enc_align_received +
                    enc_buf_bytes;

            end
            else if (enc_take_mac) begin

                enc_align_data <=
                    append_data(
                        enc_align_data,
                        enc_align_count,
                        {mac_append_reg,96'b0},
                        5'd4
                    );

                enc_align_count <=
                    enc_align_count + 6'd4;

                enc_align_received <=
                    enc_align_received + 32'd4;

                mac_appended <= 1'b1;

            end
            else if (enc_core_input_fire) begin

                enc_align_data <=
                    {enc_align_data[127:0],128'b0};

                if (enc_align_count >= 6'd16)
                    enc_align_count <=
                        enc_align_count - 6'd16;
                else
                    enc_align_count <= 6'd0;

                enc_align_sent <=
                    enc_align_sent +
                    enc_core_input_bytes;

            end

        end

    end

    // =====================================================
    // Cipher Buffer
    //
    // Independent output and INT consumers.
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            cipher_buf_data <= 128'b0;
            cipher_buf_bytes <= 5'b0;
            cipher_buf_last <= 1'b0;

            cipher_buf_valid <= 1'b0;

            cipher_output_pending <= 1'b0;
            cipher_int_pending <= 1'b0;

        end
        else if (process_start) begin

            cipher_buf_valid <= 1'b0;

            cipher_output_pending <= 1'b0;
            cipher_int_pending <= 1'b0;

        end
        else begin

            if (enc_core_output_fire) begin

                cipher_buf_data <=
                    enc_core_output_data;

                cipher_buf_bytes <=
                    enc_core_output_bytes;

                cipher_buf_last <=
                    enc_core_output_last;

                cipher_buf_valid <= 1'b1;

                cipher_output_pending <= 1'b1;

                cipher_int_pending <=
                    (mode_reg == MODE_ENC2INT);

            end

            if (cipher_output_fire)
                cipher_output_pending <= 1'b0;

            if (int_take_cipher)
                cipher_int_pending <= 1'b0;

            if (
                cipher_buf_valid &&
                (!cipher_output_pending ||
                 cipher_output_fire) &&
                (!cipher_int_pending ||
                 int_take_cipher)
            )
                cipher_buf_valid <= 1'b0;

        end

    end

    // =====================================================
    // INT Alignment
    //
    // MODE1/2/4:
    //   INT Only + Original ENC Data
    //
    // MODE3:
    //   INT Only + Cipher Data
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            int_align_data <= 256'b0;
            int_align_count <= 6'b0;

            int_align_received <= 32'b0;
            int_align_sent <= 32'b0;

        end
        else if (process_start) begin

            int_align_data <= 256'b0;
            int_align_count <= 6'b0;

            int_align_received <= 32'b0;
            int_align_sent <= 32'b0;

        end
        else begin

            if (int_take_int_only) begin

                int_align_data <=
                    append_data(
                        int_align_data,
                        int_align_count,
                        int_only_stage_data,
                        int_only_stage_bytes
                    );

                int_align_count <=
                    int_align_count +
                    int_only_stage_bytes;

                int_align_received <=
                    int_align_received +
                    int_only_stage_bytes;

            end
            else if (int_take_original) begin

                int_align_data <=
                    append_data(
                        int_align_data,
                        int_align_count,
                        enc_buf_data,
                        enc_buf_bytes
                    );

                int_align_count <=
                    int_align_count +
                    enc_buf_bytes;

                int_align_received <=
                    int_align_received +
                    enc_buf_bytes;

            end
            else if (int_take_cipher) begin

                int_align_data <=
                    append_data(
                        int_align_data,
                        int_align_count,
                        cipher_buf_data,
                        cipher_buf_bytes
                    );

                int_align_count <=
                    int_align_count +
                    cipher_buf_bytes;

                int_align_received <=
                    int_align_received +
                    cipher_buf_bytes;

            end
            else if (int_align_output_load) begin

                int_align_data <=
                    {int_align_data[127:0],128'b0};

                if (int_align_count >= 6'd16)
                    int_align_count <=
                        int_align_count - 6'd16;
                else
                    int_align_count <= 6'd0;

                int_align_sent <=
                    int_align_sent +
                    (
                        (int_bytes_remaining >= 32'd16)
                        ? 32'd16
                        : int_bytes_remaining
                    );

            end

        end

    end

    // =====================================================
    // INT Output Register
    //
    // Independent INT Core / INT Move handshake.
    // =====================================================

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            int_out_data <= 128'b0;
            int_out_bytes <= 5'b0;
            int_out_last <= 1'b0;

            int_out_valid <= 1'b0;

            int_core_pending <= 1'b0;
            int_move_pending <= 1'b0;

        end
        else if (process_start) begin

            int_out_valid <= 1'b0;

            int_core_pending <= 1'b0;
            int_move_pending <= 1'b0;

        end
        else begin

            if (int_align_output_load) begin

                int_out_data <=
                    int_align_data[255:128];

                int_out_bytes <=
                    (int_bytes_remaining >= 32'd16)
                    ? 5'd16
                    : int_bytes_remaining[4:0];

                int_out_last <=
                    (int_bytes_remaining <= 32'd16);

                int_out_valid <= 1'b1;

                int_core_pending <= 1'b1;
                int_move_pending <= int_move_reg;

            end

            if (int_core_fire)
                int_core_pending <= 1'b0;

            if (int_move_fire)
                int_move_pending <= 1'b0;

            if (
                int_out_valid &&
                (!int_core_pending || int_core_fire) &&
                (!int_move_pending || int_move_fire)
            )
                int_out_valid <= 1'b0;

        end

    end

endmodule