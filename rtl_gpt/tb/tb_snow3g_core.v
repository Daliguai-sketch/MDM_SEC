module tb_snow3g_core;

    parameter CLK_PERIOD = 10;

    parameter GOLDEN_NUM = 256;

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

    reg [31:0] golden [0:GOLDEN_NUM-1];

    integer test_id;

    integer error_count;
    integer word_count;

    integer cycle_count;
    integer last_output_cycle;

    integer interval_error_count;

    integer req_count;
    integer out_count;

    integer timeout_count;

    integer random_seed;

    reg random_req_enable;
    reg random_ready_enable;

    reg [31:0] held_stream;
    reg        held_valid;

    reg test_running;

    localparam [127:0] KEY0 =
        128'h4881FF48952C491082C5B300ABD6459F;

    localparam [127:0] IV0 =
        128'hF800000036AF6144F800000036AF6144;


    snow3g_core dut (
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


    initial begin
        clk = 1'b0;

        forever #(CLK_PERIOD / 2)
            clk = ~clk;
    end


    initial begin
        $readmemh(
            "tb/golden/snow3g_stream.hex",
            golden
        );
    end


    initial begin
        if (!$value$plusargs("TEST=%d", test_id))
            test_id = -1;

        random_seed = 32'h12345678;

        rst_n = 1'b0;

        i_init = 1'b0;

        i_key = KEY0;
        i_iv  = IV0;

        i_stream_req   = 1'b0;
        i_stream_ready = 1'b0;

        error_count = 0;

        word_count = 0;

        cycle_count = 0;

        last_output_cycle = -1;

        interval_error_count = 0;

        req_count = 0;
        out_count = 0;

        timeout_count = 0;

        random_req_enable   = 1'b0;
        random_ready_enable = 1'b0;

        held_stream = 32'b0;
        held_valid  = 1'b0;

        test_running = 1'b0;

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

        $display("");
        $display("======================================");

        if (error_count == 0)
            $display("SNOW3G CORE ALL SELECTED TESTS PASS");
        else
            $display(
                "SNOW3G CORE FAIL, errors=%0d",
                error_count
            );

        $display("======================================");

        $finish;
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
     * Start initialization.
     *
     * Drive inputs on falling edge to avoid
     * testbench/DUT sampling races.
     */

    task init_core;

        begin

            @(negedge clk);

            i_stream_req   = 1'b0;
            i_stream_ready = 1'b0;

            i_key = KEY0;
            i_iv  = IV0;

            timeout_count = 0;

            while (o_init_ready !== 1'b1 &&
                   timeout_count < 1000) begin

                @(negedge clk);
                timeout_count = timeout_count + 1;

            end

            if (timeout_count >= 1000) begin

                $display(
                    "[ERROR] Initialization input timeout"
                );

                error_count = error_count + 1;

            end

            i_init = 1'b1;

            @(negedge clk);

            i_init = 1'b0;

            timeout_count = 0;

            while (o_core_ready !== 1'b1 &&
                   timeout_count < 1000) begin

                @(negedge clk);
                timeout_count = timeout_count + 1;

            end

            if (timeout_count >= 1000) begin

                $display(
                    "[ERROR] Core ready timeout"
                );

                error_count = error_count + 1;

            end

        end

    endtask


    /*
     * Common stream test engine.
     *
     * req_gap_mode:
     *   0 = continuous requests
     *   1 = periodic request gaps
     *   2 = random request gaps
     *
     * ready_mode:
     *   0 = always ready
     *   1 = periodic backpressure
     *   2 = random backpressure
     */

    task run_stream_test;

        input integer num_words;

        input integer req_gap_mode;
        input integer ready_mode;

        input integer check_throughput;

        integer local_cycle;
        integer accepted_req;
        integer accepted_out;

        integer previous_out_cycle;

        integer local_timeout;

        reg next_req;
        reg next_ready;

        begin

            init_core();

            accepted_req = 0;
            accepted_out = 0;

            previous_out_cycle = -1;

            local_cycle = 0;
            local_timeout = 0;

            @(negedge clk);

            while (accepted_out < num_words &&
                   local_timeout < 100000) begin

                /*
                 * Request generation
                 */

                next_req = 1'b0;

                if (accepted_req < num_words) begin

                    case (req_gap_mode)

                        0: next_req = 1'b1;

                        1: next_req =
                            ((local_cycle % 7) < 4);

                        2: next_req =
                            (($random(random_seed) & 32'h7) < 5);

                        default:
                            next_req = 1'b1;

                    endcase

                end


                /*
                 * Output ready generation
                 */

                case (ready_mode)

                    0: next_ready = 1'b1;

                    1: next_ready =
                        ((local_cycle % 11) < 6);

                    2: next_ready =
                        (($random(random_seed) & 32'h7) < 5);

                    default:
                        next_ready = 1'b1;

                endcase


                i_stream_req   = next_req;
                i_stream_ready = next_ready;


                /*
                 * Sample handshake at the next rising edge.
                 *
                 * Inputs remain unchanged until the following
                 * falling edge.
                 */

                @(posedge clk);

                if (i_stream_req &&
                    o_stream_req_ready) begin

                    accepted_req = accepted_req + 1;

                end


                if (o_stream_vld &&
                    i_stream_ready) begin

                    if (accepted_out >= GOLDEN_NUM) begin

                        $display(
                            "[ERROR] Golden index overflow"
                        );

                        error_count = error_count + 1;

                    end
                    else if (o_stream !== golden[accepted_out]) begin

                        $display(
                            "[ERROR] WORD=%0d RTL=%08h GOLDEN=%08h",
                            accepted_out,
                            o_stream,
                            golden[accepted_out]
                        );

                        error_count = error_count + 1;

                    end


                    /*
                     * Continuous throughput check
                     */

                    if (check_throughput &&
                        previous_out_cycle >= 0) begin

                        if ((cycle_count -
                             previous_out_cycle) != 1) begin

                            $display(
                                "[PERF ERROR] WORD=%0d INTERVAL=%0d",
                                accepted_out,
                                cycle_count -
                                previous_out_cycle
                            );

                            error_count = error_count + 1;

                        end

                    end

                    previous_out_cycle = cycle_count;

                    accepted_out = accepted_out + 1;

                end


                @(negedge clk);

                local_cycle = local_cycle + 1;
                local_timeout = local_timeout + 1;

            end


            i_stream_req   = 1'b0;
            i_stream_ready = 1'b0;


            if (local_timeout >= 100000) begin

                $display(
                    "[ERROR] Stream timeout"
                );

                error_count = error_count + 1;

            end


            if (accepted_req != num_words) begin

                $display(
                    "[ERROR] Request count mismatch: %0d / %0d",
                    accepted_req,
                    num_words
                );

                error_count = error_count + 1;

            end


            if (accepted_out != num_words) begin

                $display(
                    "[ERROR] Output count mismatch: %0d / %0d",
                    accepted_out,
                    num_words
                );

                error_count = error_count + 1;

            end


            $display(
                "[INFO] req=%0d out=%0d cycles=%0d",
                accepted_req,
                accepted_out,
                local_cycle
            );

            repeat (5)
                @(negedge clk);

        end

    endtask


    /*
     * TEST0
     *
     * 256-word Golden comparison
     */

    task run_test0;

        integer before_errors;

        begin

            $display("");
            $display("[TEST0] 256-word Golden comparison");

            before_errors = error_count;

            run_stream_test(
                256,
                0,
                0,
                0
            );

            if (error_count == before_errors)
                $display("[TEST0] PASS");
            else
                $display("[TEST0] FAIL");

        end

    endtask


    /*
     * TEST1
     *
     * Strict one-word-per-cycle throughput
     */

    task run_test1;

        integer before_errors;

        begin

            $display("");
            $display("[TEST1] Continuous throughput");

            before_errors = error_count;

            run_stream_test(
                256,
                0,
                0,
                1
            );

            if (error_count == before_errors)
                $display("[TEST1] PASS");
            else
                $display("[TEST1] FAIL");

        end

    endtask


    /*
     * TEST2
     *
     * Periodic request gaps
     */

    task run_test2;

        integer before_errors;

        begin

            $display("");
            $display("[TEST2] Non-continuous requests");

            before_errors = error_count;

            run_stream_test(
                256,
                1,
                0,
                0
            );

            if (error_count == before_errors)
                $display("[TEST2] PASS");
            else
                $display("[TEST2] FAIL");

        end

    endtask


    /*
     * TEST3
     *
     * Output backpressure
     */

    task run_test3;

        integer before_errors;

        begin

            $display("");
            $display("[TEST3] Output backpressure");

            before_errors = error_count;

            run_stream_test(
                256,
                0,
                1,
                0
            );

            if (error_count == before_errors)
                $display("[TEST3] PASS");
            else
                $display("[TEST3] FAIL");

        end

    endtask


    /*
     * TEST4
     *
     * Key/IV reinitialization
     */

    task run_test4;

        integer before_errors;

        begin

            $display("");
            $display("[TEST4] Key/IV reinitialization");

            before_errors = error_count;

            /*
             * First initialization
             */

            run_stream_test(
                128,
                0,
                0,
                1
            );

            /*
             * Second initialization using the same Key/IV.
             *
             * The output must restart from Golden Word 0.
             */

            run_stream_test(
                256,
                0,
                0,
                1
            );

            if (error_count == before_errors)
                $display("[TEST4] PASS");
            else
                $display("[TEST4] FAIL");

        end

    endtask


    /*
     * TEST5
     *
     * Random request gaps and random backpressure
     */

    task run_test5;

        integer before_errors;

        begin

            $display("");
            $display("[TEST5] Random handshake stress");

            before_errors = error_count;

            run_stream_test(
                256,
                2,
                2,
                0
            );

            if (error_count == before_errors)
                $display("[TEST5] PASS");
            else
                $display("[TEST5] FAIL");

        end

    endtask

endmodule