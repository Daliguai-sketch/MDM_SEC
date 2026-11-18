module tb_zuc_core;

    parameter CLK_PERIOD = 10;
    parameter GOLDEN_NUM = 2048;

    reg clk;
    reg rst_n;

    reg         i_init;
    wire        o_init_ready;

    reg [127:0] i_key;
    reg [127:0] i_iv;

    wire        o_core_ready;

    reg         i_stream_req;
    wire        o_stream_req_ready;

    wire [31:0] o_stream;
    wire        o_stream_vld;
    reg         i_stream_ready;

    wire        o_busy;

    reg [31:0] golden0 [0:GOLDEN_NUM-1];
    reg [31:0] golden1 [0:GOLDEN_NUM-1];

    integer test_id;
    integer error_count;
    integer cycle_count;
    integer random_seed;

    integer protocol_error_count;

    reg        stall_prev;
    reg [31:0] stall_data;

    localparam [127:0] KEY0 =
        128'h4881FF48952C491082C5B300ABD6459F;

    localparam [127:0] IV0 =
        128'hF800000036AF6144F800000036AF6144;

    localparam [127:0] KEY1 =
        128'h000102030405060708090A0B0C0D0E0F;

    localparam [127:0] IV1 =
        128'h00000000111111112222222233333333;


    zuc_core dut (
        .clk                (clk),
        .rst_n              (rst_n),

        .i_init             (i_init),
        .o_init_ready       (o_init_ready),

        .i_key              (i_key),
        .i_iv               (i_iv),

        .o_core_ready       (o_core_ready),

        .i_stream_req       (i_stream_req),
        .o_stream_req_ready (o_stream_req_ready),

        .o_stream           (o_stream),
        .o_stream_vld       (o_stream_vld),
        .i_stream_ready     (i_stream_ready),

        .o_busy             (o_busy)
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
            "tb/golden/zuc_stream.hex",
            golden0
        );

        $readmemh(
            "tb/golden/zuc_stream_key1.hex",
            golden1
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
     * Valid/Ready protocol monitor.
     *
     * If output was stalled in previous cycle,
     * valid and data must remain unchanged.
     */

    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            stall_prev <= 1'b0;
            stall_data <= 32'b0;

            protocol_error_count <= 0;

        end
        else begin

            if (stall_prev) begin

                if (o_stream_vld !== 1'b1) begin

                    $display(
                        "[PROTO ERROR] Valid dropped during stall"
                    );

                    protocol_error_count <=
                        protocol_error_count + 1;

                end
                else if (o_stream !== stall_data) begin

                    $display(
                        "[PROTO ERROR] Data changed during stall"
                    );

                    protocol_error_count <=
                        protocol_error_count + 1;

                end

            end


            stall_prev <=
                o_stream_vld &&
                !i_stream_ready;

            stall_data <= o_stream;

        end

    end


    /*
     * Initialize Core.
     */

    task init_core;

        input [127:0] key;
        input [127:0] iv;

        integer timeout;

        begin

            @(negedge clk);

            i_stream_req   = 1'b0;
            i_stream_ready = 1'b0;

            i_key = key;
            i_iv  = iv;

            timeout = 0;

            while (o_init_ready !== 1'b1 &&
                   timeout < 10000) begin

                @(negedge clk);
                timeout = timeout + 1;

            end

            if (timeout >= 10000) begin

                $display("[ERROR] Init ready timeout");
                error_count = error_count + 1;

            end


            i_init = 1'b1;

            @(negedge clk);

            i_init = 1'b0;


            timeout = 0;

            while (o_core_ready !== 1'b1 &&
                   timeout < 10000) begin

                @(negedge clk);
                timeout = timeout + 1;

            end

            if (timeout >= 10000) begin

                $display("[ERROR] Core ready timeout");
                error_count = error_count + 1;

            end

        end

    endtask


    /*
     * Common stream test.
     *
     * gap_mode:
     *   0: continuous
     *   1: periodic gaps
     *   2: random gaps
     *
     * ready_mode:
     *   0: always ready
     *   1: periodic backpressure
     *   2: random backpressure
     *
     * golden_sel:
     *   0: KEY0/IV0
     *   1: KEY1/IV1
     */

    task run_stream_test;

        input integer num_words;

        input integer gap_mode;
        input integer ready_mode;

        input integer check_throughput;

        input integer golden_sel;

        input [127:0] key;
        input [127:0] iv;

        integer sent_req;
        integer received_words;

        integer local_cycle;
        integer timeout;

        integer previous_cycle;

        integer before_errors;

        reg next_req;
        reg next_ready;

        reg [31:0] expected_word;

        begin

            before_errors = error_count;

            init_core(key, iv);

            sent_req = 0;
            received_words = 0;

            local_cycle = 0;
            timeout = 0;

            previous_cycle = -1;

            while (received_words < num_words &&
                   timeout < 100000) begin

                @(negedge clk);

                /*
                 * Request generation
                 */

                next_req = 1'b0;

                if (sent_req < num_words) begin

                    case (gap_mode)

                        0:
                            next_req = 1'b1;

                        1:
                            next_req =
                                ((local_cycle % 7) < 4);

                        2:
                            next_req =
                                (($random(random_seed) &
                                  32'h7) < 5);

                        default:
                            next_req = 1'b1;

                    endcase

                end


                /*
                 * Output Ready
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


                i_stream_req = next_req;
                i_stream_ready = next_ready;


                /*
                 * Handshake
                 */

                @(posedge clk);

                if (i_stream_req &&
                    o_stream_req_ready) begin

                    sent_req = sent_req + 1;

                end


                if (o_stream_vld &&
                    i_stream_ready) begin

                    if (received_words < GOLDEN_NUM) begin

                        if (golden_sel == 0)
                            expected_word =
                                golden0[received_words];
                        else
                            expected_word =
                                golden1[received_words];

                        if (o_stream !== expected_word) begin

                            $display(
                                "[ERROR] WORD=%0d RTL=%08h GOLDEN=%08h",
                                received_words,
                                o_stream,
                                expected_word
                            );

                            error_count = error_count + 1;

                        end

                    end
                    else begin

                        $display(
                            "[ERROR] Golden overflow"
                        );

                        error_count = error_count + 1;

                    end


                    /*
                     * Strict throughput
                     */

                    if (check_throughput &&
                        previous_cycle >= 0) begin

                        if ((cycle_count -
                             previous_cycle) != 1) begin

                            $display(
                                "[PERF ERROR] WORD=%0d INTERVAL=%0d",
                                received_words,
                                cycle_count -
                                previous_cycle
                            );

                            error_count = error_count + 1;

                        end

                    end


                    previous_cycle = cycle_count;

                    received_words = received_words + 1;

                end


                local_cycle = local_cycle + 1;
                timeout = timeout + 1;

            end


            @(negedge clk);

            i_stream_req   = 1'b0;
            i_stream_ready = 1'b0;


            if (timeout >= 100000) begin

                $display("[ERROR] Stream timeout");
                error_count = error_count + 1;

            end


            if (sent_req != num_words) begin

                $display(
                    "[ERROR] Request count=%0d expected=%0d",
                    sent_req,
                    num_words
                );

                error_count = error_count + 1;

            end


            if (received_words != num_words) begin

                $display(
                    "[ERROR] Output count=%0d expected=%0d",
                    received_words,
                    num_words
                );

                error_count = error_count + 1;

            end


            $display(
                "[INFO] req=%0d out=%0d cycles=%0d",
                sent_req,
                received_words,
                local_cycle
            );


            if (error_count == before_errors)
                $display("[INFO] Stream test PASS");
            else
                $display("[INFO] Stream test FAIL");

            repeat (5)
                @(negedge clk);

        end

    endtask


    /*
     * TEST0: 256-word Golden
     */

    task run_test0;

        integer before_errors;

        begin

            $display("");
            $display("[TEST0] 256-word Golden");

            before_errors = error_count;

            run_stream_test(
                256, 0, 0, 0, 0, KEY0, IV0
            );

            if (error_count == before_errors)
                $display("[TEST0] PASS");
            else
                $display("[TEST0] FAIL");

        end

    endtask


    /*
     * TEST1: 2048-word throughput
     */

    task run_test1;

        integer before_errors;

        begin

            $display("");
            $display("[TEST1] 2048-word throughput");

            before_errors = error_count;

            run_stream_test(
                2048, 0, 0, 1, 0, KEY0, IV0
            );

            if (error_count == before_errors)
                $display("[TEST1] PASS");
            else
                $display("[TEST1] FAIL");

        end

    endtask


    /*
     * TEST2: Periodic request gaps
     */

    task run_test2;

        integer before_errors;

        begin

            $display("");
            $display("[TEST2] Periodic request gaps");

            before_errors = error_count;

            run_stream_test(
                512, 1, 0, 0, 0, KEY0, IV0
            );

            if (error_count == before_errors)
                $display("[TEST2] PASS");
            else
                $display("[TEST2] FAIL");

        end

    endtask


    /*
     * TEST3: Output backpressure
     */

    task run_test3;

        integer before_errors;

        begin

            $display("");
            $display("[TEST3] Output backpressure");

            before_errors = error_count;

            run_stream_test(
                512, 0, 2, 0, 0, KEY0, IV0
            );

            if (error_count == before_errors)
                $display("[TEST3] PASS");
            else
                $display("[TEST3] FAIL");

        end

    endtask


    /*
     * TEST4: Reinitialization
     */

    task run_test4;

        integer before_errors;

        begin

            $display("");
            $display("[TEST4] Reinitialization");

            before_errors = error_count;

            run_stream_test(
                256, 0, 0, 1, 0, KEY0, IV0
            );

            run_stream_test(
                512, 0, 0, 1, 0, KEY0, IV0
            );

            if (error_count == before_errors)
                $display("[TEST4] PASS");
            else
                $display("[TEST4] FAIL");

        end

    endtask


    /*
     * TEST5: Random handshake
     */

    task run_test5;

        integer before_errors;

        begin

            $display("");
            $display("[TEST5] Random handshake");

            before_errors = error_count;

            run_stream_test(
                1024, 2, 2, 0, 0, KEY0, IV0
            );

            if (error_count == before_errors)
                $display("[TEST5] PASS");
            else
                $display("[TEST5] FAIL");

        end

    endtask


    /*
     * TEST6: Key/IV switching
     */

    task run_test6;

        integer before_errors;

        begin

            $display("");
            $display("[TEST6] Key/IV switching");

            before_errors = error_count;

            run_stream_test(
                256, 0, 0, 1, 0, KEY0, IV0
            );

            run_stream_test(
                256, 0, 0, 1, 1, KEY1, IV1
            );

            run_stream_test(
                256, 0, 0, 1, 0, KEY0, IV0
            );

            if (error_count == before_errors)
                $display("[TEST6] PASS");
            else
                $display("[TEST6] FAIL");

        end

    endtask


    /*
     * Main
     */

    initial begin

        if (!$value$plusargs("TEST=%d", test_id))
            test_id = -1;

        rst_n = 1'b0;

        i_init = 1'b0;

        i_key = KEY0;
        i_iv  = IV0;

        i_stream_req = 1'b0;
        i_stream_ready = 1'b0;

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


        $display("");
        $display("======================================");

        if (error_count == 0 &&
            protocol_error_count == 0) begin

            $display("ZUC CORE ALL SELECTED TESTS PASS");

        end
        else begin

            $display(
                "ZUC CORE FAIL errors=%0d protocol_errors=%0d",
                error_count,
                protocol_error_count
            );

        end

        $display("======================================");

        $finish;

    end

endmodule