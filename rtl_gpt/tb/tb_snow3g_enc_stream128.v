module tb_snow3g_enc_stream128;

    parameter CLK_PERIOD = 10;
    parameter GOLDEN_BLOCKS = 512;

    reg clk;
    reg rst_n;

    reg         i_start;
    wire        o_start_ready;

    reg [127:0] i_key;
    reg [127:0] i_iv;

    reg [15:0]  i_block_num;

    wire [127:0] o_stream;
    wire         o_stream_vld;
    reg          i_stream_ready;

    wire         o_busy;
    wire         o_done;

    reg [127:0] golden [0:GOLDEN_BLOCKS-1];

    integer test_id;
    integer error_count;
    integer cycle_count;
    integer random_seed;

    localparam [127:0] KEY0 =
        128'h4881FF48952C491082C5B300ABD6459F;

    localparam [127:0] IV0 =
        128'hF800000036AF6144F800000036AF6144;


    snow3g_enc_stream128 dut (
        .clk            (clk),
        .rst_n          (rst_n),

        .i_start        (i_start),
        .o_start_ready  (o_start_ready),

        .i_key          (i_key),
        .i_iv           (i_iv),

        .i_block_num    (i_block_num),

        .o_stream       (o_stream),
        .o_stream_vld   (o_stream_vld),
        .i_stream_ready (i_stream_ready),

        .o_busy         (o_busy),
        .o_done         (o_done)
    );


    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD/2)
            clk = ~clk;
    end


    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cycle_count <= 0;
        else
            cycle_count <= cycle_count + 1;
    end


    initial begin
        $readmemh(
            "tb/golden/snow3g_stream128.hex",
            golden
        );
    end


    /*
     * Start one transaction
     */

    task start_transaction;

        input integer blocks;

        integer timeout;

        begin

            @(negedge clk);

            timeout = 0;

            while (o_start_ready !== 1'b1 &&
                   timeout < 10000) begin

                @(negedge clk);
                timeout = timeout + 1;

            end

            if (timeout >= 10000) begin

                $display("[ERROR] Start ready timeout");
                error_count = error_count + 1;

            end

            i_key = KEY0;
            i_iv  = IV0;

            i_block_num = blocks;

            i_start = 1'b1;

            @(negedge clk);

            i_start = 1'b0;

        end

    endtask


    /*
     * Run one transaction
     *
     * ready_mode:
     *   0 = always ready
     *   1 = periodic backpressure
     *   2 = random backpressure
     */

    task run_transaction;

        input integer blocks;
        input integer ready_mode;
        input integer check_throughput;

        integer before_errors;

        integer received_blocks;

        integer previous_cycle;

        integer local_cycle;

        integer timeout;

        integer done_count;

        reg next_ready;

        begin

            before_errors = error_count;

            received_blocks = 0;

            previous_cycle = -1;

            local_cycle = 0;

            timeout = 0;

            done_count = 0;

            start_transaction(blocks);

            while (timeout < 100000 &&
                   done_count == 0) begin

                @(negedge clk);

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

                i_stream_ready = next_ready;

                @(posedge clk);

                if (o_stream_vld &&
                    i_stream_ready) begin

                    if (received_blocks >= blocks) begin

                        $display(
                            "[ERROR] Extra output block"
                        );

                        error_count = error_count + 1;

                    end
                    else if (received_blocks >= GOLDEN_BLOCKS) begin

                        $display(
                            "[ERROR] Golden index overflow"
                        );

                        error_count = error_count + 1;

                    end
                    else if (o_stream !== golden[received_blocks]) begin

                        $display(
                            "[ERROR] BLOCK=%0d RTL=%032h GOLDEN=%032h",
                            received_blocks,
                            o_stream,
                            golden[received_blocks]
                        );

                        error_count = error_count + 1;

                    end


                    if (check_throughput &&
                        previous_cycle >= 0) begin

                        if ((cycle_count - previous_cycle) != 4) begin

                            $display(
                                "[PERF ERROR] BLOCK=%0d INTERVAL=%0d",
                                received_blocks,
                                cycle_count - previous_cycle
                            );

                            error_count = error_count + 1;

                        end

                    end

                    previous_cycle = cycle_count;

                    received_blocks = received_blocks + 1;

                end


                if (o_done)
                    done_count = done_count + 1;


                local_cycle = local_cycle + 1;
                timeout = timeout + 1;

            end


            @(negedge clk);

            i_stream_ready = 1'b0;


            if (timeout >= 100000) begin

                $display("[ERROR] Transaction timeout");

                error_count = error_count + 1;

            end


            if (received_blocks != blocks) begin

                $display(
                    "[ERROR] Received=%0d Expected=%0d",
                    received_blocks,
                    blocks
                );

                error_count = error_count + 1;

            end


            if (done_count != 1) begin

                $display(
                    "[ERROR] Done count=%0d",
                    done_count
                );

                error_count = error_count + 1;

            end


            repeat (5)
                @(negedge clk);


            if (o_done) begin

                $display(
                    "[ERROR] Done did not return low"
                );

                error_count = error_count + 1;

            end


            if (!o_start_ready) begin

                $display(
                    "[ERROR] Start ready not restored"
                );

                error_count = error_count + 1;

            end


            if (error_count == before_errors)
                $display(
                    "[INFO] Transaction PASS: blocks=%0d cycles=%0d",
                    blocks,
                    local_cycle
                );
            else
                $display(
                    "[INFO] Transaction FAIL: blocks=%0d",
                    blocks
                );

        end

    endtask


    task run_test0;
        integer before_errors;
        begin
            $display("[TEST0] Single block");
            before_errors = error_count;

            run_transaction(1, 0, 0);

            if (error_count == before_errors)
                $display("[TEST0] PASS");
            else
                $display("[TEST0] FAIL");
        end
    endtask


    task run_test1;
        integer before_errors;
        begin
            $display("[TEST1] 64-block throughput");
            before_errors = error_count;

            run_transaction(64, 0, 1);

            if (error_count == before_errors)
                $display("[TEST1] PASS");
            else
                $display("[TEST1] FAIL");
        end
    endtask


    task run_test2;
        integer before_errors;
        begin
            $display("[TEST2] 256-block throughput");
            before_errors = error_count;

            run_transaction(256, 0, 1);

            if (error_count == before_errors)
                $display("[TEST2] PASS");
            else
                $display("[TEST2] FAIL");
        end
    endtask


    task run_test3;
        integer before_errors;
        begin
            $display("[TEST3] Random backpressure");
            before_errors = error_count;

            run_transaction(128, 2, 0);

            if (error_count == before_errors)
                $display("[TEST3] PASS");
            else
                $display("[TEST3] FAIL");
        end
    endtask


    task run_test4;
        integer before_errors;
        begin
            $display("[TEST4] 521-byte packet");
            before_errors = error_count;

            // ceil(521 / 16) = 33 blocks
            run_transaction(33, 0, 1);

            if (error_count == before_errors)
                $display("[TEST4] PASS");
            else
                $display("[TEST4] FAIL");
        end
    endtask


    task run_test5;
        integer before_errors;
        begin
            $display("[TEST5] Reinitialization");
            before_errors = error_count;

            run_transaction(32, 0, 1);
            run_transaction(64, 0, 1);
            run_transaction(128, 2, 0);

            if (error_count == before_errors)
                $display("[TEST5] PASS");
            else
                $display("[TEST5] FAIL");
        end
    endtask


    task run_test6;
        integer before_errors;
        begin
            $display("[TEST6] Zero blocks");
            before_errors = error_count;

            run_transaction(0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST6] PASS");
            else
                $display("[TEST6] FAIL");
        end
    endtask


    task run_test7;
        integer before_errors;
        begin
            $display("[TEST7] Multiple transactions");
            before_errors = error_count;

            run_transaction(1,   0, 0);
            run_transaction(16,  1, 0);
            run_transaction(64,  2, 0);
            run_transaction(256, 0, 1);
            run_transaction(33,  2, 0);
            run_transaction(0,   0, 0);

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

        i_start = 1'b0;

        i_key = KEY0;
        i_iv = IV0;

        i_block_num = 16'd0;

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
            $display("SNOW3G ENC STREAM128 ALL TESTS PASS");
        else
            $display(
                "SNOW3G ENC STREAM128 FAIL errors=%0d",
                error_count
            );

        $display("======================================");

        $finish;

    end

endmodule