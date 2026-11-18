module tb_zuc_int;

    parameter CLK_PERIOD = 10;

    reg clk;
    reg rst_n;

    reg         i_start;
    wire        o_start_ready;

    reg [127:0] i_key;

    reg [31:0]  i_count;
    reg [4:0]   i_bearer;
    reg         i_direction;

    reg [31:0]  i_msg_len;

    reg [31:0]  i_data;
    reg         i_data_vld;
    wire        o_data_ready;
    reg [2:0]   i_valid_bytes;

    wire [31:0] o_mac;
    wire        o_mac_vld;
    reg         i_mac_ready;

    wire        o_busy;

    reg [31:0] golden [0:23];

    integer test_id;
    integer error_count;
    integer cycle_count;
    integer random_seed;

    integer protocol_error_count;

    reg        mac_stall_prev;
    reg [31:0] mac_stall_data;

    localparam [127:0] KEY0 =
        128'hF172263558DA301944A74CF383FD23A2;

    localparam [127:0] KEY1 =
        128'h000102030405060708090A0B0C0D0E0F;

    localparam [31:0] COUNT0 = 32'h36AF6144;
    localparam [31:0] COUNT1 = 32'h12345678;

    localparam [4:0] BEARER0 = 5'd31;
    localparam [4:0] BEARER1 = 5'd7;


    zuc_int dut (
        .clk            (clk),
        .rst_n          (rst_n),

        .i_start        (i_start),
        .o_start_ready  (o_start_ready),

        .i_key          (i_key),

        .i_count        (i_count),
        .i_bearer       (i_bearer),
        .i_direction    (i_direction),

        .i_msg_len      (i_msg_len),

        .i_data         (i_data),
        .i_data_vld     (i_data_vld),
        .o_data_ready   (o_data_ready),
        .i_valid_bytes  (i_valid_bytes),

        .o_mac          (o_mac),
        .o_mac_vld      (o_mac_vld),
        .i_mac_ready    (i_mac_ready),

        .o_busy         (o_busy)
    );


    /*
     * Clock
     */

    initial begin

        clk = 1'b0;

        forever #(CLK_PERIOD / 2)
            clk = ~clk;

    end


    /*
     * Golden
     */

    initial begin

        $readmemh(
            "tb/golden/zuc_mac_golden.hex",
            golden
        );

    end


    /*
     * Cycle counter
     */

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;

    end


    /*
     * MAC output stability monitor.
     *
     * Valid and MAC data must remain stable
     * while downstream Ready is low.
     */

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            mac_stall_prev <= 1'b0;
            mac_stall_data <= 32'b0;

            protocol_error_count <= 0;

        end
        else begin

            if (mac_stall_prev) begin

                if (o_mac_vld !== 1'b1) begin

                    $display(
                        "[PROTO ERROR] MAC valid dropped"
                    );

                    protocol_error_count <=
                        protocol_error_count + 1;

                end
                else if (o_mac !== mac_stall_data) begin

                    $display(
                        "[PROTO ERROR] MAC changed during stall"
                    );

                    protocol_error_count <=
                        protocol_error_count + 1;

                end

            end


            mac_stall_prev <=
                o_mac_vld &&
                !i_mac_ready;

            mac_stall_data <= o_mac;

        end

    end


    /*
     * Deterministic message byte.
     *
     * MSG[i] = i & 0xFF
     */

    function [7:0] msg_byte;

        input integer index;

        begin
            msg_byte = index & 8'hFF;
        end

    endfunction


    /*
     * Generate one 32-bit message Word.
     *
     * MSB-first.
     */

    function [31:0] make_data;

        input integer offset;

        integer k;

        begin

            make_data = 32'b0;

            for (k = 0; k < 4; k = k + 1) begin

                make_data[31-k*8 -: 8] =
                    msg_byte(offset + k);

            end

        end

    endfunction


    /*
     * Run one MAC transaction.
     *
     * gap_mode:
     *   0 = continuous input
     *   1 = periodic gaps
     *   2 = random gaps
     *
     * ready_mode:
     *   0 = always ready
     *   1 = periodic output backpressure
     *   2 = random output backpressure
     */

    task run_transaction;

        input integer case_index;
        input integer length;

        input [127:0] key;
        input [31:0] count;
        input [4:0] bearer;
        input direction;

        input integer gap_mode;
        input integer ready_mode;

        input integer check_throughput;

        integer before_errors;

        integer sent_bytes;
        integer valid_bytes;

        integer local_cycle;
        integer timeout;

        integer mac_count;

        integer previous_data_cycle;
        integer current_data_cycle;

        integer interval;

        reg next_valid;
        reg next_ready;

        begin

            before_errors = error_count;

            sent_bytes = 0;

            local_cycle = 0;
            timeout = 0;

            mac_count = 0;

            previous_data_cycle = -1;


            /*
             * Wait for transaction start ready.
             */

            @(negedge clk);

            while (o_start_ready !== 1'b1 &&
                   timeout < 100000) begin

                @(negedge clk);
                timeout = timeout + 1;

            end

            if (timeout >= 100000) begin

                $display("[ERROR] Start ready timeout");
                error_count = error_count + 1;

            end


            /*
             * Start transaction.
             */

            i_key = key;

            i_count = count;
            i_bearer = bearer;
            i_direction = direction;

            i_msg_len = length;

            i_start = 1'b1;

            @(negedge clk);

            i_start = 1'b0;


            /*
             * Input data and wait for MAC.
             */

            timeout = 0;

            while (mac_count == 0 &&
                   timeout < 200000) begin

                @(negedge clk);


                /*
                 * Input Valid
                 */

                next_valid = 1'b0;

                if (sent_bytes < length) begin

                    case (gap_mode)

                        0:
                            next_valid = 1'b1;

                        1:
                            next_valid =
                                ((local_cycle % 7) < 4);

                        2:
                            next_valid =
                                (($random(random_seed) &
                                  32'h7) < 5);

                        default:
                            next_valid = 1'b1;

                    endcase

                end


                /*
                 * MAC output Ready
                 */

                case (ready_mode)

                    0:
                        next_ready = 1'b1;

                    1:
                        next_ready =
                            ((local_cycle % 11) < 6);

                    2:
                        next_ready =
                            (($random(random_seed) &
                              32'h7) < 5);

                    default:
                        next_ready = 1'b1;

                endcase


                i_data_vld = next_valid;
                i_mac_ready = next_ready;

                i_data = make_data(sent_bytes);


                if ((length - sent_bytes) >= 4)
                    valid_bytes = 4;
                else
                    valid_bytes = length - sent_bytes;

                i_valid_bytes = valid_bytes;


                /*
                 * Sample input/output handshakes.
                 */

                @(posedge clk);

                if (i_data_vld &&
                    o_data_ready) begin

                    sent_bytes =
                        sent_bytes + valid_bytes;


                    /*
                     * Strict throughput check.
                     *
                     * Only enabled for continuous input.
                     */

                    current_data_cycle = cycle_count;

                    if (check_throughput &&
                        previous_data_cycle >= 0) begin

                        interval =
                            current_data_cycle -
                            previous_data_cycle;

                        if (interval != 1) begin

                            $display(
                                "[PERF ERROR] CASE=%0d BYTE=%0d INTERVAL=%0d",
                                case_index,
                                sent_bytes,
                                interval
                            );

                            error_count = error_count + 1;

                        end

                    end

                    previous_data_cycle =
                        current_data_cycle;

                end


                if (o_mac_vld &&
                    i_mac_ready) begin

                    if (o_mac !== golden[case_index]) begin

                        $display(
                            "[ERROR] CASE=%0d LEN=%0d RTL=%08h GOLDEN=%08h",
                            case_index,
                            length,
                            o_mac,
                            golden[case_index]
                        );

                        error_count = error_count + 1;

                    end

                    mac_count = mac_count + 1;

                end


                local_cycle = local_cycle + 1;
                timeout = timeout + 1;

            end


            /*
             * Stop driving
             */

            @(negedge clk);

            i_data_vld = 1'b0;
            i_mac_ready = 1'b0;


            /*
             * Result checks
             */

            if (timeout >= 200000) begin

                $display(
                    "[ERROR] MAC timeout CASE=%0d",
                    case_index
                );

                error_count = error_count + 1;

            end


            if (sent_bytes != length) begin

                $display(
                    "[ERROR] Sent bytes=%0d expected=%0d",
                    sent_bytes,
                    length
                );

                error_count = error_count + 1;

            end


            if (mac_count != 1) begin

                $display(
                    "[ERROR] MAC count=%0d",
                    mac_count
                );

                error_count = error_count + 1;

            end


            repeat (5)
                @(negedge clk);


            if (!o_start_ready) begin

                $display(
                    "[ERROR] Core did not return IDLE"
                );

                error_count = error_count + 1;

            end


            if (error_count == before_errors)
                $display(
                    "[INFO] CASE=%0d LEN=%0d PASS cycles=%0d",
                    case_index,
                    length,
                    local_cycle
                );
            else
                $display(
                    "[INFO] CASE=%0d LEN=%0d FAIL",
                    case_index,
                    length
                );

        end

    endtask


    /*
     * TEST0
     *
     * Basic lengths
     */

    task run_test0;

        integer before_errors;

        begin

            $display("");
            $display("[TEST0] Basic lengths");

            before_errors = error_count;

            run_transaction(0,  0,  KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(1,  1,  KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(2,  2,  KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(3,  3,  KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(4,  4,  KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(5,  5,  KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(6,  7,  KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(7,  8,  KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(8,  9,  KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(9,  13, KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(10, 16, KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(11, 17, KEY0, COUNT0, BEARER0, 0, 0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST0] PASS");
            else
                $display("[TEST0] FAIL");

        end

    endtask


    /*
     * TEST1: Long messages
     */

    task run_test1;

        integer before_errors;

        begin

            $display("");
            $display("[TEST1] Long messages");

            before_errors = error_count;

            run_transaction(12, 32,   KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(13, 128,  KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(14, 4096, KEY0, COUNT0, BEARER0, 0, 0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST1] PASS");
            else
                $display("[TEST1] FAIL");

        end

    endtask


    /*
     * TEST2: Strict throughput
     */

    task run_test2;

        integer before_errors;

        begin

            $display("");
            $display("[TEST2] 4096-byte throughput");

            before_errors = error_count;

            run_transaction(14, 4096, KEY0, COUNT0, BEARER0, 0, 0, 0, 1);

            if (error_count == before_errors)
                $display("[TEST2] PASS");
            else
                $display("[TEST2] FAIL");

        end

    endtask


    /*
     * TEST3: Random input gaps
     */

    task run_test3;

        integer before_errors;

        begin

            $display("");
            $display("[TEST3] Random input gaps");

            before_errors = error_count;

            run_transaction(15, 4096, KEY0, COUNT0, BEARER0, 0, 2, 0, 0);

            if (error_count == before_errors)
                $display("[TEST3] PASS");
            else
                $display("[TEST3] FAIL");

        end

    endtask


    /*
     * TEST4: MAC output backpressure
     */

    task run_test4;

        integer before_errors;

        begin

            $display("");
            $display("[TEST4] MAC output backpressure");

            before_errors = error_count;

            run_transaction(16, 128, KEY0, COUNT0, BEARER0, 0, 0, 2, 0);

            if (error_count == before_errors)
                $display("[TEST4] PASS");
            else
                $display("[TEST4] FAIL");

        end

    endtask


    /*
     * TEST5: COUNT / BEARER / DIRECTION
     */

    task run_test5;

        integer before_errors;

        begin

            $display("");
            $display("[TEST5] IV parameter update");

            before_errors = error_count;

            run_transaction(17, 128, KEY0, COUNT1, BEARER0, 0, 0, 0, 0);
            run_transaction(18, 128, KEY0, COUNT0, BEARER1, 0, 0, 0, 0);
            run_transaction(19, 128, KEY0, COUNT0, BEARER0, 1, 0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST5] PASS");
            else
                $display("[TEST5] FAIL");

        end

    endtask


    /*
     * TEST6: Key update
     */

    task run_test6;

        integer before_errors;

        begin

            $display("");
            $display("[TEST6] Key update");

            before_errors = error_count;

            run_transaction(20, 128, KEY1, COUNT0, BEARER0, 0, 0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST6] PASS");
            else
                $display("[TEST6] FAIL");

        end

    endtask


    /*
     * TEST7: Key0 -> Key1 -> Key0
     */

    task run_test7;

        integer before_errors;

        begin

            $display("");
            $display("[TEST7] Key switching");

            before_errors = error_count;

            run_transaction(21, 64, KEY0, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(22, 64, KEY1, COUNT0, BEARER0, 0, 0, 0, 0);
            run_transaction(23, 64, KEY0, COUNT0, BEARER0, 0, 0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST7] PASS");
            else
                $display("[TEST7] FAIL");

        end

    endtask


    /*
     * TEST8: Random combined
     */

    task run_test8;

        integer before_errors;

        begin

            $display("");
            $display("[TEST8] Random combined");

            before_errors = error_count;

            run_transaction(9,  13,   KEY0, COUNT0, BEARER0, 0, 2, 2, 0);
            run_transaction(13, 128,  KEY0, COUNT0, BEARER0, 0, 2, 2, 0);
            run_transaction(14, 4096, KEY0, COUNT0, BEARER0, 0, 2, 2, 0);

            if (error_count == before_errors)
                $display("[TEST8] PASS");
            else
                $display("[TEST8] FAIL");

        end

    endtask


    /*
     * Main
     */

    initial begin

        if (!$value$plusargs("TEST=%d", test_id))
            test_id = -1;

        rst_n = 1'b0;

        i_start = 1'b0;

        i_key = KEY0;

        i_count = COUNT0;
        i_bearer = BEARER0;
        i_direction = 1'b0;

        i_msg_len = 32'd0;

        i_data = 32'b0;
        i_data_vld = 1'b0;

        i_valid_bytes = 3'd0;

        i_mac_ready = 1'b0;

        error_count = 0;
        cycle_count = 0;

        random_seed = 32'h12345678;

        repeat (10)
            @(posedge clk);

        @(negedge clk);
        rst_n = 1'b1;

        repeat (5)
            @(posedge clk);


        if (test_id == -1 || test_id == 0)
            run_test0();

        if (test_id == -1 || test_id == 1)
            run_test1();

        if (test_id == -1 || test_id == 2)
            run_test2();

        if (test_id == -1 || test_id == 3)
            run_test3();

        if (test_id == -1 || test_id == 4)
            run_test4();

        if (test_id == -1 || test_id == 5)
            run_test5();

        if (test_id == -1 || test_id == 6)
            run_test6();

        if (test_id == -1 || test_id == 7)
            run_test7();

        if (test_id == -1 || test_id == 8)
            run_test8();


        $display("");
        $display("======================================");

        if (error_count == 0 &&
            protocol_error_count == 0) begin

            $display("ZUC INT ALL SELECTED TESTS PASS");

        end
        else begin

            $display(
                "ZUC INT FAIL errors=%0d protocol_errors=%0d",
                error_count,
                protocol_error_count
            );

        end

        $display("======================================");

        $finish;

    end

endmodule