module tb_sec_process_multi_alg;

    localparam MODE_ENC_ONLY = 3'd0;
    localparam MODE_INT_ONLY = 3'd1;
    localparam MODE_INT2ENC  = 3'd2;
    localparam MODE_ENC2INT  = 3'd3;
    localparam MODE_PARALLEL = 3'd4;

    localparam ALG_AES  = 2'd0;
    localparam ALG_SNOW = 2'd1;
    localparam ALG_ZUC  = 2'd2;
    localparam ALG_NULL = 2'd3;

    localparam MAX_BLOCKS = 1024;

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

    // =====================================================
    // DUT
    // =====================================================

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
    // Configuration
    // =====================================================

    integer test_id;
    integer enc_alg;
    integer int_alg;

    integer error_count;

    integer a_len;
    integer b_len;

    integer cipher_expected_len;
    integer int_expected_len;

    integer cipher_recv_count;
    integer int_recv_count;
    integer mac_recv_count;

    integer expected_mac_count;

    integer random_enable;

    reg [2:0] mode_cfg;
    reg move_cfg;

    reg [127:0] cipher_golden [0:MAX_BLOCKS-1];
    reg [127:0] int_move_golden [0:MAX_BLOCKS-1];
    reg [31:0] mac_golden [0:0];

    reg [1023:0] cipher_file;
    reg [1023:0] int_file;
    reg [1023:0] mac_file;

    integer j;
    integer k;

    // =====================================================
    // Golden Reader
    // =====================================================

    task load_golden;

        begin

            $sformat(
                cipher_file,
                "tb/golden/sec_process_multi_alg/e%0d_i%0d_case_%02d_cipher.hex",
                enc_alg,
                int_alg,
                test_id
            );

            $sformat(
                int_file,
                "tb/golden/sec_process_multi_alg/e%0d_i%0d_case_%02d_int_move.hex",
                enc_alg,
                int_alg,
                test_id
            );

            $sformat(
                mac_file,
                "tb/golden/sec_process_multi_alg/e%0d_i%0d_case_%02d_mac.hex",
                enc_alg,
                int_alg,
                test_id
            );

            for (k = 0; k < MAX_BLOCKS; k = k + 1) begin

                cipher_golden[k] = 128'b0;
                int_move_golden[k] = 128'b0;

            end

            mac_golden[0] = 32'b0;

            if (cipher_expected_len != 0)
                $readmemh(cipher_file, cipher_golden);

            if (int_expected_len != 0)
                $readmemh(int_file, int_move_golden);

            if (expected_mac_count != 0)
                $readmemh(mac_file, mac_golden);

        end

    endtask

    // =====================================================
    // Golden Byte Extraction
    // =====================================================

    function [7:0] get_cipher_byte;

        input integer index;

        begin

            get_cipher_byte =
                cipher_golden[index/16]
                    [127-(index%16)*8 -: 8];

        end

    endfunction

    function [7:0] get_int_byte;

        input integer index;

        begin

            get_int_byte =
                int_move_golden[index/16]
                    [127-(index%16)*8 -: 8];

        end

    endfunction

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
    // Start
    // =====================================================

    task start_transaction;

        begin

            @(negedge clk);

            i_mode = mode_cfg;
            i_int_move = move_cfg;

            i_enc_alg_sel = enc_alg;
            i_int_alg_sel = int_alg;

            if (enc_alg == ALG_AES)
                i_enc_key =
                    128'hF172263558DA301944A74CF383FD23A2;
            else
                i_enc_key =
                    128'h4881FF48952C491082C5B300ABD6459F;

            if (int_alg == ALG_AES)
                i_int_key =
                    128'h000102030405060708090A0B0C0D0E0F;
            else
                i_int_key =
                    128'h4881FF48952C491082C5B300ABD6459F;

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
    // =====================================================

    task send_inputs;

        integer sent;
        integer n;
        integer m;

        reg [127:0] block_data;

        begin

            // INT Only first
            sent = 0;

            while (sent < a_len) begin

                n = a_len - sent;

                if (n > 16)
                    n = 16;

                block_data = 128'b0;

                for (m = 0; m < n; m = m + 1)
                    block_data[127-m*8 -: 8] =
                        (sent+m+8'h31) & 8'hFF;

                @(negedge clk);

                i_int_only_data = block_data;
                i_int_only_valid_bytes = n;
                i_int_only_data_last =
                    ((sent+n) == a_len);

                i_int_only_data_vld = 1'b1;

                begin : WAIT_A

                    while (1) begin

                        @(posedge clk);

                        if (o_int_only_data_ready)
                            disable WAIT_A;

                    end

                end

                sent = sent + n;

                @(negedge clk);
                i_int_only_data_vld = 1'b0;

                if (random_enable)
                    repeat (($random & 3))
                        @(posedge clk);

            end

            // ENC Data second
            sent = 0;

            while (sent < b_len) begin

                n = b_len - sent;

                if (n > 16)
                    n = 16;

                block_data = 128'b0;

                for (m = 0; m < n; m = m + 1)
                    block_data[127-m*8 -: 8] =
                        (sent+m+8'hA5) & 8'hFF;

                @(negedge clk);

                i_enc_data = block_data;
                i_enc_valid_bytes = n;
                i_enc_data_last =
                    ((sent+n) == b_len);

                i_enc_data_vld = 1'b1;

                begin : WAIT_B

                    while (1) begin

                        @(posedge clk);

                        if (o_enc_data_ready)
                            disable WAIT_B;

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
    // Cipher Monitor
    // =====================================================

    always @(posedge clk) begin

        if (
            rst_n &&
            o_cipher_data_vld &&
            i_cipher_data_ready
        ) begin

            for (j = 0; j < o_cipher_valid_bytes; j = j + 1) begin

                if (
                    o_cipher_data[127-j*8 -: 8] !==
                    get_cipher_byte(cipher_recv_count+j)
                ) begin

                    $display(
                        "[CIPHER ERROR] IDX=%0d EXP=%02X GOT=%02X",
                        cipher_recv_count+j,
                        get_cipher_byte(cipher_recv_count+j),
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

    end

    // =====================================================
    // INT Move Monitor
    // =====================================================

    always @(posedge clk) begin

        if (
            rst_n &&
            o_int_move_data_vld &&
            i_int_move_data_ready
        ) begin

            for (j = 0; j < o_int_move_valid_bytes; j = j + 1) begin

                if (
                    o_int_move_data[127-j*8 -: 8] !==
                    get_int_byte(int_recv_count+j)
                ) begin

                    $display(
                        "[INT MOVE ERROR] IDX=%0d EXP=%02X GOT=%02X",
                        int_recv_count+j,
                        get_int_byte(int_recv_count+j),
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

    end

    // =====================================================
    // MAC Monitor
    // =====================================================

    always @(posedge clk) begin

        if (
            rst_n &&
            o_mac_vld &&
            i_mac_ready
        ) begin

            mac_recv_count =
                mac_recv_count + 1;

            if (o_mac !== mac_golden[0]) begin

                $display(
                    "[MAC ERROR] EXP=%08X GOT=%08X",
                    mac_golden[0],
                    o_mac
                );

                error_count = error_count + 1;

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
    // Run Case
    // =====================================================

    task run_case;

        begin

            cipher_recv_count = 0;
            int_recv_count = 0;
            mac_recv_count = 0;

            if (mode_cfg == MODE_INT_ONLY)
                cipher_expected_len = 0;
            else if (mode_cfg == MODE_INT2ENC)
                cipher_expected_len = b_len + 4;
            else
                cipher_expected_len = b_len;

            if (mode_cfg == MODE_ENC_ONLY)
                int_expected_len = 0;
            else
                int_expected_len = a_len + b_len;

            if (mode_cfg == MODE_ENC_ONLY)
                expected_mac_count = 0;
            else
                expected_mac_count = 1;

            load_golden;

            $display(
                "[CASE START] TEST=%0d MODE=%0d ENC_ALG=%0d INT_ALG=%0d A=%0d B=%0d",
                test_id,
                mode_cfg,
                enc_alg,
                int_alg,
                a_len,
                b_len
            );

            start_transaction;

            fork

                send_inputs;

                begin
                    wait(o_done);
                end

            join

            repeat (4) @(posedge clk);

            if (cipher_recv_count != cipher_expected_len) begin

                $display(
                    "[CIPHER COUNT ERROR] EXP=%0d GOT=%0d",
                    cipher_expected_len,
                    cipher_recv_count
                );

                error_count = error_count + 1;

            end

            if (
                move_cfg &&
                int_recv_count != int_expected_len
            ) begin

                $display(
                    "[INT MOVE COUNT ERROR] EXP=%0d GOT=%0d",
                    int_expected_len,
                    int_recv_count
                );

                error_count = error_count + 1;

            end

            if (
                !move_cfg &&
                int_recv_count != 0
            ) begin

                $display("[INT MOVE DISABLED ERROR]");
                error_count = error_count + 1;

            end

            if (mac_recv_count != expected_mac_count) begin

                $display(
                    "[MAC COUNT ERROR] EXP=%0d GOT=%0d",
                    expected_mac_count,
                    mac_recv_count
                );

                error_count = error_count + 1;

            end

        end

    endtask

    // =====================================================
    // Timeout
    // =====================================================

    initial begin

        #10000000;

        $display("SEC PROCESS MULTI ALG TIMEOUT");

        $finish;

    end

    // =====================================================
    // Main
    // =====================================================

    initial begin

        test_id = 0;
        enc_alg = 1;
        int_alg = 1;

        error_count = 0;
        random_enable = 0;

        i_start = 1'b0;

        i_mode = MODE_ENC_ONLY;
        i_int_move = 1'b0;

        i_enc_alg_sel = ALG_AES;
        i_int_alg_sel = ALG_AES;

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

        if (!$value$plusargs("ENC_ALG=%d", enc_alg))
            enc_alg = 1;

        if (!$value$plusargs("INT_ALG=%d", int_alg))
            int_alg = 1;

        if (enc_alg < 0 || enc_alg > 3 ||
            int_alg < 0 || int_alg > 3) begin

            $display("INVALID ALGORITHM");

            $finish;

        end

        case (test_id)

            0: begin
                mode_cfg = MODE_ENC_ONLY;
                a_len = 0;
                b_len = 128;
                move_cfg = 0;
            end

            1: begin
                mode_cfg = MODE_INT_ONLY;
                a_len = 13;
                b_len = 21;
                move_cfg = 1;
            end

            2: begin
                mode_cfg = MODE_INT2ENC;
                a_len = 13;
                b_len = 21;
                move_cfg = 1;
            end

            3: begin
                mode_cfg = MODE_ENC2INT;
                a_len = 13;
                b_len = 21;
                move_cfg = 1;
            end

            4: begin
                mode_cfg = MODE_PARALLEL;
                a_len = 13;
                b_len = 21;
                move_cfg = 1;
            end

            5: begin
                mode_cfg = MODE_INT2ENC;
                a_len = 5;
                b_len = 15;
                move_cfg = 1;
            end

            6: begin
                mode_cfg = MODE_INT2ENC;
                a_len = 0;
                b_len = 16;
                move_cfg = 0;
            end

            7: begin
                mode_cfg = MODE_ENC2INT;
                a_len = 5;
                b_len = 32;
                move_cfg = 1;
            end

            8: begin
                mode_cfg = MODE_INT_ONLY;
                a_len = 0;
                b_len = 0;
                move_cfg = 1;
            end

            9: begin
                mode_cfg = MODE_ENC_ONLY;
                a_len = 0;
                b_len = 0;
                move_cfg = 0;
            end

            10: begin
                mode_cfg = MODE_PARALLEL;
                a_len = 13;
                b_len = 65;
                move_cfg = 1;
                random_enable = 1;
            end

            11: begin
                mode_cfg = MODE_INT2ENC;
                a_len = 13;
                b_len = 128;
                move_cfg = 1;
            end

            default: begin

                $display("INVALID TEST");

                $finish;

            end

        endcase

        reset_dut;

        run_case;

        if (error_count == 0)
            $display(
                "SEC PROCESS MULTI ALG TEST%0d ENC=%0d INT=%0d PASS",
                test_id,
                enc_alg,
                int_alg
            );
        else
            $display(
                "SEC PROCESS MULTI ALG TEST%0d ENC=%0d INT=%0d FAIL ERRORS=%0d",
                test_id,
                enc_alg,
                int_alg,
                error_count
            );

        $finish;

    end

endmodule