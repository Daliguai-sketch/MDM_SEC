module tb_sec_process_ctrl;

    localparam MODE_ENC_ONLY = 3'd0;
    localparam MODE_INT_ONLY = 3'd1;
    localparam MODE_INT2ENC  = 3'd2;
    localparam MODE_ENC2INT  = 3'd3;
    localparam MODE_PARALLEL = 3'd4;

    localparam ALG_NULL = 2'd3;

    reg clk;
    reg rst_n;

    reg i_start;
    wire o_start_ready;

    reg [2:0] i_mode;
    reg i_int_move;

    reg [1:0] i_enc_alg_sel;
    reg [1:0] i_int_alg_sel;

    reg [127:0] i_enc_key;
    reg [127:0] i_int_key;

    reg [31:0] i_count;
    reg [4:0] i_bearer;
    reg i_direction;

    reg [31:0] i_int_only_bytes;
    reg [31:0] i_enc_bytes;

    reg [127:0] i_int_only_data;
    reg i_int_only_data_vld;
    wire o_int_only_data_ready;
    reg i_int_only_data_last;
    reg [4:0] i_int_only_valid_bytes;

    reg [127:0] i_enc_data;
    reg i_enc_data_vld;
    wire o_enc_data_ready;
    reg i_enc_data_last;
    reg [4:0] i_enc_valid_bytes;

    wire [127:0] o_cipher_data;
    wire o_cipher_data_vld;
    reg i_cipher_data_ready;
    wire o_cipher_data_last;
    wire [4:0] o_cipher_valid_bytes;

    wire [127:0] o_int_move_data;
    wire o_int_move_data_vld;
    reg i_int_move_data_ready;
    wire o_int_move_data_last;
    wire [4:0] o_int_move_valid_bytes;

    wire [31:0] o_mac;
    wire o_mac_vld;
    reg i_mac_ready;

    wire o_busy;
    wire o_done;

    sec_process_ctrl dut (
        .clk(clk),
        .rst_n(rst_n),

        .i_start(i_start),
        .o_start_ready(o_start_ready),

        .i_mode(i_mode),
        .i_int_move(i_int_move),

        .i_enc_alg_sel(i_enc_alg_sel),
        .i_int_alg_sel(i_int_alg_sel),

        .i_enc_key(i_enc_key),
        .i_int_key(i_int_key),

        .i_count(i_count),
        .i_bearer(i_bearer),
        .i_direction(i_direction),

        .i_int_only_bytes(i_int_only_bytes),
        .i_enc_bytes(i_enc_bytes),

        .i_int_only_data(i_int_only_data),
        .i_int_only_data_vld(i_int_only_data_vld),
        .o_int_only_data_ready(o_int_only_data_ready),
        .i_int_only_data_last(i_int_only_data_last),
        .i_int_only_valid_bytes(i_int_only_valid_bytes),

        .i_enc_data(i_enc_data),
        .i_enc_data_vld(i_enc_data_vld),
        .o_enc_data_ready(o_enc_data_ready),
        .i_enc_data_last(i_enc_data_last),
        .i_enc_valid_bytes(i_enc_valid_bytes),

        .o_cipher_data(o_cipher_data),
        .o_cipher_data_vld(o_cipher_data_vld),
        .i_cipher_data_ready(i_cipher_data_ready),
        .o_cipher_data_last(o_cipher_data_last),
        .o_cipher_valid_bytes(o_cipher_valid_bytes),

        .o_int_move_data(o_int_move_data),
        .o_int_move_data_vld(o_int_move_data_vld),
        .i_int_move_data_ready(i_int_move_data_ready),
        .o_int_move_data_last(o_int_move_data_last),
        .o_int_move_valid_bytes(o_int_move_valid_bytes),

        .o_mac(o_mac),
        .o_mac_vld(o_mac_vld),
        .i_mac_ready(i_mac_ready),

        .o_busy(o_busy),
        .o_done(o_done)
    );

    // =====================================================
    // Clock
    // =====================================================

    initial clk = 1'b0;
    always #5 clk = ~clk;

    // =====================================================
    // Test Configuration
    // =====================================================

    integer test_id;
    integer error_count;

    integer a_len;
    integer b_len;

    integer cipher_expected_len;
    integer int_expected_len;

    integer cipher_recv_count;
    integer int_recv_count;
    integer mac_recv_count;

    integer cycle_count;

    reg [2:0] mode_cfg;
    reg move_cfg;

    reg random_enable;

    // =====================================================
    // Test Data Arrays
    // =====================================================

    reg [7:0] int_only_mem [0:8191];
    reg [7:0] enc_mem      [0:8191];

    reg [7:0] cipher_expected [0:8195];
    reg [7:0] int_expected    [0:16383];

    integer i;
    integer j;

    // =====================================================
    // Golden Generator
    // =====================================================

    task build_golden;

        integer k;

        begin

            for (k = 0; k < a_len; k = k + 1)
                int_only_mem[k] = (k + 8'h31) & 8'hFF;

            for (k = 0; k < b_len; k = k + 1)
                enc_mem[k] = (k + 8'hA5) & 8'hFF;

            cipher_expected_len = 0;
            int_expected_len = 0;

            if (mode_cfg != MODE_INT_ONLY) begin

                for (k = 0; k < b_len; k = k + 1)
                    cipher_expected[k] = enc_mem[k];

                cipher_expected_len = b_len;

                if (mode_cfg == MODE_INT2ENC) begin

                    for (k = 0; k < 4; k = k + 1)
                        cipher_expected[b_len+k] = 8'h00;

                    cipher_expected_len = b_len + 4;

                end

            end

            if (mode_cfg != MODE_ENC_ONLY) begin

                for (k = 0; k < a_len; k = k + 1)
                    int_expected[k] = int_only_mem[k];

                for (k = 0; k < b_len; k = k + 1)
                    int_expected[a_len+k] = enc_mem[k];

                int_expected_len = a_len + b_len;

            end

        end

    endtask

    // =====================================================
    // Reset
    // =====================================================

    task reset_dut;

        begin

            rst_n = 1'b0;

            i_start = 1'b0;

            i_int_only_data_vld = 1'b0;
            i_enc_data_vld = 1'b0;

            i_cipher_data_ready = 1'b0;
            i_int_move_data_ready = 1'b0;
            i_mac_ready = 1'b0;

            repeat (8) @(posedge clk);

            @(negedge clk);
            rst_n = 1'b1;

            repeat (4) @(posedge clk);

        end

    endtask

    // =====================================================
    // Start Transaction
    // =====================================================

    task start_transaction;

        begin

            @(negedge clk);

            i_mode = mode_cfg;
            i_int_move = move_cfg;

            i_enc_alg_sel = ALG_NULL;
            i_int_alg_sel = ALG_NULL;

            i_enc_key =
                128'hF172263558DA301944A74CF383FD23A2;

            i_int_key =
                128'h000102030405060708090A0B0C0D0E0F;

            i_count = 32'h36AF6144;
            i_bearer = 5'd31;
            i_direction = 1'b1;

            i_int_only_bytes = a_len;
            i_enc_bytes = b_len;

            while (!o_start_ready)
                @(negedge clk);

            i_start = 1'b1;

            @(negedge clk);

            i_start = 1'b0;

        end

    endtask

    // =====================================================
    // Input Driver
    //
    // INT Only Data first, ENC Data second.
    // =====================================================

    task send_inputs;

        integer sent;
        integer n;
        integer k;

        reg [127:0] block_data;

        begin

            // ---------------------------------------------
            // INT Only Data
            // ---------------------------------------------

            sent = 0;

            while (sent < a_len) begin

                n = a_len - sent;

                if (n > 16)
                    n = 16;

                block_data = 128'b0;

                for (k = 0; k < n; k = k + 1)
                    block_data[127-k*8 -: 8] =
                        int_only_mem[sent+k];

                @(negedge clk);

                i_int_only_data = block_data;
                i_int_only_valid_bytes = n;
                i_int_only_data_last =
                    ((sent+n) == a_len);

                i_int_only_data_vld = 1'b1;

                begin : WAIT_A_READY

                    while (1) begin

                        @(posedge clk);

                        if (o_int_only_data_ready)
                            disable WAIT_A_READY;

                    end

                end

                sent = sent + n;

                @(negedge clk);
                i_int_only_data_vld = 1'b0;

                if (random_enable)
                    repeat (($random & 3))
                        @(posedge clk);

            end

            // ---------------------------------------------
            // ENC Data
            // ---------------------------------------------

            sent = 0;

            while (sent < b_len) begin

                n = b_len - sent;

                if (n > 16)
                    n = 16;

                block_data = 128'b0;

                for (k = 0; k < n; k = k + 1)
                    block_data[127-k*8 -: 8] =
                        enc_mem[sent+k];

                @(negedge clk);

                i_enc_data = block_data;
                i_enc_valid_bytes = n;
                i_enc_data_last =
                    ((sent+n) == b_len);

                i_enc_data_vld = 1'b1;

                begin : WAIT_B_READY

                    while (1) begin

                        @(posedge clk);

                        if (o_enc_data_ready)
                            disable WAIT_B_READY;

                    end

                end

                sent = sent + n;

                @(negedge clk);
                i_enc_data_vld = 1'b0;

                if (random_enable)
                    repeat (($random & 3))
                        @(posedge clk);

            end

        end

    endtask

    // =====================================================
    // Output Monitor
    // =====================================================

    always @(posedge clk) begin

        if (rst_n) begin

            if (
                o_cipher_data_vld &&
                i_cipher_data_ready
            ) begin

                for (j = 0; j < o_cipher_valid_bytes; j = j + 1) begin

                    if (
                        o_cipher_data[127-j*8 -: 8] !==
                        cipher_expected[cipher_recv_count+j]
                    ) begin

                        $display(
                            "[CIPHER ERROR] INDEX=%0d EXP=%02X GOT=%02X",
                            cipher_recv_count+j,
                            cipher_expected[cipher_recv_count+j],
                            o_cipher_data[127-j*8 -: 8]
                        );

                        error_count = error_count + 1;

                    end

                end

                cipher_recv_count =
                    cipher_recv_count +
                    o_cipher_valid_bytes;

                if (
                    o_cipher_data_last !==
                    (cipher_recv_count == cipher_expected_len)
                ) begin

                    $display("[CIPHER LAST ERROR]");
                    error_count = error_count + 1;

                end

            end

            if (
                o_int_move_data_vld &&
                i_int_move_data_ready
            ) begin

                for (j = 0; j < o_int_move_valid_bytes; j = j + 1) begin

                    if (
                        o_int_move_data[127-j*8 -: 8] !==
                        int_expected[int_recv_count+j]
                    ) begin

                        $display(
                            "[INT MOVE ERROR] INDEX=%0d EXP=%02X GOT=%02X",
                            int_recv_count+j,
                            int_expected[int_recv_count+j],
                            o_int_move_data[127-j*8 -: 8]
                        );

                        error_count = error_count + 1;

                    end

                end

                int_recv_count =
                    int_recv_count +
                    o_int_move_valid_bytes;

                if (
                    o_int_move_data_last !==
                    (int_recv_count == int_expected_len)
                ) begin

                    $display("[INT MOVE LAST ERROR]");
                    error_count = error_count + 1;

                end

            end

            if (
                o_mac_vld &&
                i_mac_ready
            ) begin

                mac_recv_count =
                    mac_recv_count + 1;

                if (o_mac !== 32'h00000000) begin

                    $display(
                        "[MAC ERROR] EXP=00000000 GOT=%08X",
                        o_mac
                    );

                    error_count =
                        error_count + 1;

                end

            end

        end

    end

    // =====================================================
    // Ready Generator
    // =====================================================

    always @(negedge clk) begin

        if (!rst_n) begin

            i_cipher_data_ready = 1'b0;
            i_int_move_data_ready = 1'b0;
            i_mac_ready = 1'b0;

        end
        else if (random_enable) begin

            i_cipher_data_ready =
                (($random & 3) != 0);

            i_int_move_data_ready =
                (($random & 3) != 0);

            i_mac_ready =
                (($random & 3) != 0);

        end
        else begin

            i_cipher_data_ready = 1'b1;
            i_int_move_data_ready = 1'b1;
            i_mac_ready = 1'b1;

        end

    end

    // =====================================================
    // Run One Case
    // =====================================================

    task run_case;

        input [2:0] mode_in;
        input integer a_in;
        input integer b_in;
        input move_in;
        input random_in;

        integer expected_mac_count;

        begin

            mode_cfg = mode_in;
            a_len = a_in;
            b_len = b_in;

            move_cfg = move_in;
            random_enable = random_in;

            cipher_recv_count = 0;
            int_recv_count = 0;
            mac_recv_count = 0;

            build_golden;

            if (mode_cfg == MODE_ENC_ONLY)
                expected_mac_count = 0;
            else
                expected_mac_count = 1;

            $display(
                "[CASE START] MODE=%0d A=%0d B=%0d MOVE=%0d RANDOM=%0d",
                mode_cfg,
                a_len,
                b_len,
                move_cfg,
                random_enable
            );

            start_transaction;

            fork

                send_inputs;

                begin

                    wait(o_done);

                end

            join

            repeat (4) @(posedge clk);

            if (
                cipher_recv_count !=
                cipher_expected_len
            ) begin

                $display(
                    "[CIPHER COUNT ERROR] EXP=%0d GOT=%0d",
                    cipher_expected_len,
                    cipher_recv_count
                );

                error_count = error_count + 1;

            end

            if (
                move_cfg &&
                int_recv_count !=
                int_expected_len
            ) begin

                $display(
                    "[INT MOVE COUNT ERROR] EXP=%0d GOT=%0d",
                    int_expected_len,
                    int_recv_count
                );

                error_count = error_count + 1;

            end

            if (!move_cfg && int_recv_count != 0) begin

                $display("[INT MOVE DISABLED ERROR]");
                error_count = error_count + 1;

            end

            if (
                mac_recv_count !=
                expected_mac_count
            ) begin

                $display(
                    "[MAC COUNT ERROR] EXP=%0d GOT=%0d",
                    expected_mac_count,
                    mac_recv_count
                );

                error_count = error_count + 1;

            end

            $display(
                "[CASE END] CIPHER=%0d INT_MOVE=%0d MAC=%0d ERRORS=%0d",
                cipher_recv_count,
                int_recv_count,
                mac_recv_count,
                error_count
            );

        end

    endtask

    // =====================================================
    // Timeout
    // =====================================================

    initial begin

        #5000000;

        $display("[TIMEOUT] SEC PROCESS CTRL");

        $finish;

    end

    // =====================================================
    // Main Test
    // =====================================================

    initial begin

        test_id = 0;
        error_count = 0;

        mode_cfg = MODE_ENC_ONLY;
        move_cfg = 1'b0;
        random_enable = 1'b0;

        i_mode = 3'b0;
        i_int_move = 1'b0;

        i_enc_alg_sel = ALG_NULL;
        i_int_alg_sel = ALG_NULL;

        i_enc_key = 128'b0;
        i_int_key = 128'b0;

        i_count = 32'b0;
        i_bearer = 5'b0;
        i_direction = 1'b0;

        i_int_only_bytes = 32'b0;
        i_enc_bytes = 32'b0;

        i_int_only_data = 128'b0;
        i_int_only_data_vld = 1'b0;
        i_int_only_data_last = 1'b0;
        i_int_only_valid_bytes = 5'b0;

        i_enc_data = 128'b0;
        i_enc_data_vld = 1'b0;
        i_enc_data_last = 1'b0;
        i_enc_valid_bytes = 5'b0;

        if (!$value$plusargs("TEST=%d", test_id))
            test_id = 0;

        reset_dut;

        case (test_id)

            0:
                run_case(
                    MODE_ENC_ONLY,
                    0, 32, 0, 0
                );

            1:
                run_case(
                    MODE_INT_ONLY,
                    13, 21, 1, 0
                );

            2:
                run_case(
                    MODE_INT2ENC,
                    13, 21, 1, 0
                );

            3:
                run_case(
                    MODE_ENC2INT,
                    13, 21, 1, 0
                );

            4:
                run_case(
                    MODE_PARALLEL,
                    13, 21, 1, 0
                );

            5:
                run_case(
                    MODE_INT2ENC,
                    5, 15, 1, 0
                );

            6:
                run_case(
                    MODE_INT2ENC,
                    0, 16, 0, 0
                );

            7:
                run_case(
                    MODE_ENC2INT,
                    5, 32, 1, 0
                );

            8:
                run_case(
                    MODE_INT_ONLY,
                    0, 0, 1, 0
                );

            9:
                run_case(
                    MODE_ENC_ONLY,
                    0, 0, 0, 0
                );

            10:
                run_case(
                    MODE_PARALLEL,
                    13, 65, 1, 1
                );

            11: begin

                run_case(MODE_ENC_ONLY, 0, 32, 0, 0);
                run_case(MODE_INT_ONLY, 13, 21, 1, 0);
                run_case(MODE_INT2ENC, 5, 15, 1, 0);
                run_case(MODE_ENC2INT, 13, 21, 1, 0);
                run_case(MODE_PARALLEL, 13, 21, 1, 0);

            end

            default: begin

                $display("INVALID TEST=%0d", test_id);
                $finish;

            end

        endcase

        if (error_count == 0)
            $display("SEC PROCESS CTRL TEST%0d PASS", test_id);
        else
            $display(
                "SEC PROCESS CTRL TEST%0d FAIL ERRORS=%0d",
                test_id,
                error_count
            );

        $finish;

    end

endmodule