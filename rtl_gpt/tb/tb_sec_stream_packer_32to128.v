module tb_sec_stream_packer_32to128;

    parameter CLK_PERIOD = 10;

    parameter TOTAL_WORDS = 256;

    reg clk;
    reg rst_n;

    reg i_clear;

    reg [31:0] i_word;
    reg        i_word_vld;

    wire       o_word_ready;

    wire [127:0] o_stream;
    wire         o_stream_vld;

    reg          i_stream_ready;

    integer test_id;

    integer error_count;

    integer cycle_count;

    integer random_seed;

    integer timeout_count;

    integer last_output_cycle;

    reg [127:0] expected_block;

    reg [127:0] held_stream;

    reg held_valid;


    sec_stream_packer_32to128 dut (
        .clk            (clk),
        .rst_n          (rst_n),

        .i_clear        (i_clear),

        .i_word         (i_word),
        .i_word_vld     (i_word_vld),
        .o_word_ready   (o_word_ready),

        .o_stream       (o_stream),
        .o_stream_vld   (o_stream_vld),
        .i_stream_ready (i_stream_ready)
    );


    initial begin

        clk = 1'b0;

        forever #(CLK_PERIOD / 2)
            clk = ~clk;

    end


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;

    end


    /*
     * Expected block:
     *
     * Word0 = base + 0
     * Word1 = base + 1
     * Word2 = base + 2
     * Word3 = base + 3
     */

    function [127:0] make_expected;

        input integer base;

        begin

            make_expected = {
                base + 0,
                base + 1,
                base + 2,
                base + 3
            };

        end

    endfunction


    task clear_packer;

        begin

            @(negedge clk);

            i_word_vld = 1'b0;
            i_stream_ready = 1'b0;

            i_clear = 1'b1;

            @(negedge clk);

            i_clear = 1'b0;

        end

    endtask


    /*
     * Common streaming test.
     *
     * gap_mode:
     * 0: continuous
     * 1: periodic gaps
     * 2: random gaps
     *
     * ready_mode:
     * 0: always ready
     * 1: periodic backpressure
     * 2: random backpressure
     */

    task run_stream_test;

        input integer num_blocks;

        input integer gap_mode;

        input integer ready_mode;

        input integer check_throughput;

        integer sent_words;
        integer received_blocks;

        integer local_cycle;

        integer local_timeout;

        integer previous_output_cycle;

        reg next_valid;
        reg next_ready;

        begin

            clear_packer();

            sent_words = 0;
            received_blocks = 0;

            local_cycle = 0;

            local_timeout = 0;

            previous_output_cycle = -1;

            while (received_blocks < num_blocks &&
                   local_timeout < 100000) begin

                /*
                 * Drive at falling edge
                 */

                @(negedge clk);

                next_valid = 1'b0;

                if (sent_words < num_blocks * 4) begin

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


                i_word_vld = next_valid;

                i_word = sent_words;

                i_stream_ready = next_ready;


                /*
                 * Sample handshake
                 */

                @(posedge clk);

                if (i_word_vld && o_word_ready)
                    sent_words = sent_words + 1;


                if (o_stream_vld && i_stream_ready) begin

                    expected_block =
                        make_expected(received_blocks * 4);


                    if (o_stream !== expected_block) begin

                        $display(
                            "[ERROR] BLOCK=%0d RTL=%032h EXPECT=%032h",
                            received_blocks,
                            o_stream,
                            expected_block
                        );

                        error_count = error_count + 1;

                    end


                    if (check_throughput &&
                        previous_output_cycle >= 0) begin

                        if ((cycle_count -
                             previous_output_cycle) != 4) begin

                            $display(
                                "[PERF ERROR] BLOCK=%0d INTERVAL=%0d",
                                received_blocks,
                                cycle_count -
                                previous_output_cycle
                            );

                            error_count = error_count + 1;

                        end

                    end


                    previous_output_cycle = cycle_count;

                    received_blocks = received_blocks + 1;

                end


                local_cycle = local_cycle + 1;

                local_timeout = local_timeout + 1;

            end


            @(negedge clk);

            i_word_vld = 1'b0;

            i_stream_ready = 1'b0;


            if (local_timeout >= 100000) begin

                $display("[ERROR] Streaming timeout");

                error_count = error_count + 1;

            end


            if (sent_words != num_blocks * 4) begin

                $display(
                    "[ERROR] sent_words=%0d expected=%0d",
                    sent_words,
                    num_blocks * 4
                );

                error_count = error_count + 1;

            end


            if (received_blocks != num_blocks) begin

                $display(
                    "[ERROR] received_blocks=%0d expected=%0d",
                    received_blocks,
                    num_blocks
                );

                error_count = error_count + 1;

            end


            $display(
                "[INFO] words=%0d blocks=%0d cycles=%0d",
                sent_words,
                received_blocks,
                local_cycle
            );

        end

    endtask


    /*
     * TEST0: Basic packing
     */

    task run_test0;

        integer before_errors;

        begin

            $display("");
            $display("[TEST0] Basic packing");

            before_errors = error_count;

            run_stream_test(
                4,
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
     * TEST1: Continuous throughput
     */

    task run_test1;

        integer before_errors;

        begin

            $display("");
            $display("[TEST1] Continuous throughput");

            before_errors = error_count;

            run_stream_test(
                64,
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
     * TEST2: Input gaps
     */

    task run_test2;

        integer before_errors;

        begin

            $display("");
            $display("[TEST2] Input gaps");

            before_errors = error_count;

            run_stream_test(
                64,
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
     * TEST3: Output backpressure
     */

    task run_test3;

        integer before_errors;

        begin

            $display("");
            $display("[TEST3] Output backpressure");

            before_errors = error_count;

            run_stream_test(
                64,
                0,
                2,
                0
            );

            if (error_count == before_errors)
                $display("[TEST3] PASS");
            else
                $display("[TEST3] FAIL");

        end

    endtask


    /*
     * TEST4: Input gaps + output backpressure
     */

    task run_test4;

        integer before_errors;

        begin

            $display("");
            $display("[TEST4] Random mixed handshake");

            before_errors = error_count;

            run_stream_test(
                64,
                2,
                2,
                0
            );

            if (error_count == before_errors)
                $display("[TEST4] PASS");
            else
                $display("[TEST4] FAIL");

        end

    endtask


    /*
     * TEST5: Clear partial words
     */

    task run_test5;

        integer before_errors;

        begin

            $display("");
            $display("[TEST5] Clear partial words");

            before_errors = error_count;

            clear_packer();

            /*
             * Insert two words.
             */

            @(negedge clk);

            i_word_vld = 1'b1;
            i_word = 32'hAAAAAAAA;

            @(negedge clk);

            i_word = 32'hBBBBBBBB;

            @(negedge clk);

            i_word_vld = 1'b0;

            /*
             * Clear partial packet.
             */

            i_clear = 1'b1;

            @(negedge clk);

            i_clear = 1'b0;

            /*
             * Send a new complete block.
             */

            run_stream_test(
                1,
                0,
                0,
                0
            );

            if (error_count == before_errors)
                $display("[TEST5] PASS");
            else
                $display("[TEST5] FAIL");

        end

    endtask


    /*
     * TEST6: Clear pending output
     */

    task run_test6;

        integer before_errors;

        begin

            $display("");
            $display("[TEST6] Clear pending output");

            before_errors = error_count;

            clear_packer();

            i_stream_ready = 1'b0;

            /*
             * Generate one complete block.
             */

            @(negedge clk);

            i_word_vld = 1'b1;
            i_word = 32'h11111111;

            @(negedge clk);
            i_word = 32'h22222222;

            @(negedge clk);
            i_word = 32'h33333333;

            @(negedge clk);
            i_word = 32'h44444444;

            @(negedge clk);
            i_word_vld = 1'b0;

            if (!o_stream_vld) begin

                $display(
                    "[ERROR] Expected pending output"
                );

                error_count = error_count + 1;

            end


            /*
             * Clear pending output.
             */

            i_clear = 1'b1;

            @(negedge clk);

            i_clear = 1'b0;

            if (o_stream_vld) begin

                $display(
                    "[ERROR] Pending output not cleared"
                );

                error_count = error_count + 1;

            end


            run_stream_test(
                1,
                0,
                0,
                0
            );

            if (error_count == before_errors)
                $display("[TEST6] PASS");
            else
                $display("[TEST6] FAIL");

        end

    endtask


    /*
     * TEST7: Multiple packets
     */

    task run_test7;

        integer before_errors;

        begin

            $display("");
            $display("[TEST7] Multiple packets");

            before_errors = error_count;

            run_stream_test(
                8,
                0,
                0,
                1
            );

            run_stream_test(
                16,
                2,
                1,
                0
            );

            run_stream_test(
                64,
                0,
                2,
                0
            );

            if (error_count == before_errors)
                $display("[TEST7] PASS");
            else
                $display("[TEST7] FAIL");

        end

    endtask


    initial begin

        if (!$value$plusargs("TEST=%d", test_id))
            test_id = -1;

        rst_n = 1'b0;

        i_clear = 1'b0;

        i_word = 32'b0;

        i_word_vld = 1'b0;

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

        if (test_id == -1 || test_id == 7)
            run_test7();


        $display("");
        $display("======================================");

        if (error_count == 0)
            $display("PACKER ALL SELECTED TESTS PASS");
        else
            $display(
                "PACKER FAIL, error_count=%0d",
                error_count
            );

        $display("======================================");

        $finish;

    end

endmodule