module tb_snow3g_int;

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

    reg [63:0]  i_data;
    reg         i_data_vld;
    wire        o_data_ready;
    reg [3:0]   i_valid_bytes;

    wire [31:0] o_mac;
    wire        o_mac_vld;
    reg         i_mac_ready;

    wire        o_busy;

    reg [31:0] golden [0:19];

    integer test_id;
    integer error_count;
    integer random_seed;

    localparam [127:0] KEY0 =
        128'hF172263558DA301944A74CF383FD23A2;

    localparam [127:0] KEY1 =
        128'h000102030405060708090A0B0C0D0E0F;

    localparam [31:0] COUNT0 = 32'h36AF6144;
    localparam [31:0] COUNT1 = 32'h12345678;

    localparam [4:0] BEARER0 = 5'd31;
    localparam [4:0] BEARER1 = 5'd7;


    snow3g_int dut (
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


    initial begin
        clk = 1'b0;
        forever #(CLK_PERIOD / 2)
            clk = ~clk;
    end


    initial begin
        $readmemh(
            "tb/golden/snow3g_mac_golden.hex",
            golden
        );
    end


    /*
     * Generate deterministic message byte.
     */

    function [7:0] msg_byte;
        input integer index;
        begin
            msg_byte = index & 8'hFF;
        end
    endfunction


    /*
     * Generate 64-bit input data.
     *
     * MSB-first byte order.
     */

    function [63:0] make_data;
        input integer offset;

        integer k;

        begin
            make_data = 64'b0;

            for (k = 0; k < 8; k = k + 1)
                make_data[63 - k*8 -: 8] =
                    msg_byte(offset + k);
        end
    endfunction


    /*
     * Run one MAC transaction.
     *
     * gap_mode:
     * 0 = continuous input
     * 1 = periodic gaps
     * 2 = random gaps
     *
     * ready_mode:
     * 0 = always ready
     * 1 = periodic MAC output backpressure
     * 2 = random MAC output backpressure
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

        integer before_errors;

        integer sent_bytes;
        integer valid_bytes;

        integer local_cycle;
        integer timeout;

        integer mac_count;

        reg next_valid;
        reg next_ready;

        begin

            before_errors = error_count;

            sent_bytes = 0;
            local_cycle = 0;
            timeout = 0;
            mac_count = 0;


            /*
             * Wait for idle
             */

            @(negedge clk);

            while (o_start_ready !== 1'b1 &&
                   timeout < 100000) begin

                @(negedge clk);
                timeout = timeout + 1;

            end

            if (timeout >= 100000) begin
                $display("[ERROR] Start timeout");
                error_count = error_count + 1;
            end


            /*
             * Start MAC
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
             * Stream data and wait for MAC.
             */

            timeout = 0;

            while (mac_count == 0 &&
                   timeout < 200000) begin

                @(negedge clk);


                /*
                 * Input valid generation
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
                 * Output ready generation
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


                /*
                 * Generate next data beat.
                 *
                 * Data and byte count remain stable
                 * until a successful handshake.
                 */

                i_data = make_data(sent_bytes);

                if ((length - sent_bytes) >= 8)
                    valid_bytes = 8;
                else
                    valid_bytes = length - sent_bytes;

                i_valid_bytes = valid_bytes;


                /*
                 * Sample handshake
                 */

                @(posedge clk);

                if (i_data_vld &&
                    o_data_ready) begin

                    sent_bytes = sent_bytes + valid_bytes;

                end


                if (o_mac_vld &&
                    i_mac_ready) begin

                    if (mac_count != 0) begin

                        $display(
                            "[ERROR] Multiple MAC results"
                        );

                        error_count = error_count + 1;

                    end

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


            @(negedge clk);

            i_data_vld = 1'b0;
            i_mac_ready = 1'b0;


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
                    "[ERROR] Core did not return idle"
                );

                error_count = error_count + 1;

            end


            if (error_count == before_errors) begin

                $display(
                    "[INFO] CASE=%0d LEN=%0d PASS cycles=%0d",
                    case_index,
                    length,
                    local_cycle
                );

            end
            else begin

                $display(
                    "[INFO] CASE=%0d LEN=%0d FAIL",
                    case_index,
                    length
                );

            end

        end

    endtask


    task run_test0;
        integer before_errors;
        begin
            $display("[TEST0] Basic message lengths");
            before_errors = error_count;

            run_transaction(0, 0, KEY0, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(1, 1, KEY0, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(2, 7, KEY0, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(3, 8, KEY0, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(4, 9, KEY0, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(5, 13, KEY0, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(6, 16, KEY0, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(7, 17, KEY0, COUNT0, BEARER0, 0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST0] PASS");
            else
                $display("[TEST0] FAIL");
        end
    endtask


    task run_test1;
        integer before_errors;
        begin
            $display("[TEST1] Long messages");
            before_errors = error_count;

            run_transaction(8, 32, KEY0, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(9, 128, KEY0, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(10, 4096, KEY0, COUNT0, BEARER0, 0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST1] PASS");
            else
                $display("[TEST1] FAIL");
        end
    endtask


    task run_test2;
        integer before_errors;
        begin
            $display("[TEST2] Random input gaps");
            before_errors = error_count;

            run_transaction(11, 4096, KEY0, COUNT0, BEARER0, 0, 2, 0);

            if (error_count == before_errors)
                $display("[TEST2] PASS");
            else
                $display("[TEST2] FAIL");
        end
    endtask


    task run_test3;
        integer before_errors;
        begin
            $display("[TEST3] MAC output backpressure");
            before_errors = error_count;

            run_transaction(12, 128, KEY0, COUNT0, BEARER0, 0, 0, 2);

            if (error_count == before_errors)
                $display("[TEST3] PASS");
            else
                $display("[TEST3] FAIL");
        end
    endtask


    task run_test4;
        integer before_errors;
        begin
            $display("[TEST4] COUNT / DIRECTION / BEARER update");
            before_errors = error_count;

            run_transaction(13, 128, KEY0, COUNT1, BEARER0, 0, 0, 0);
            run_transaction(14, 128, KEY0, COUNT0, BEARER0, 1, 0, 0);
            run_transaction(15, 128, KEY0, COUNT0, BEARER1, 0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST4] PASS");
            else
                $display("[TEST4] FAIL");
        end
    endtask


    task run_test5;
        integer before_errors;
        begin
            $display("[TEST5] Different Key");
            before_errors = error_count;

            run_transaction(16, 128, KEY1, COUNT0, BEARER0, 0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST5] PASS");
            else
                $display("[TEST5] FAIL");
        end
    endtask


    task run_test6;
        integer before_errors;
        begin
            $display("[TEST6] Key0 -> Key1 -> Key0");
            before_errors = error_count;

            run_transaction(17, 64, KEY0, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(18, 64, KEY1, COUNT0, BEARER0, 0, 0, 0);
            run_transaction(19, 64, KEY0, COUNT0, BEARER0, 0, 0, 0);

            if (error_count == before_errors)
                $display("[TEST6] PASS");
            else
                $display("[TEST6] FAIL");
        end
    endtask


    task run_test7;
        integer before_errors;
        begin
            $display("[TEST7] Random combined handshake");
            before_errors = error_count;

            run_transaction(5, 13, KEY0, COUNT0, BEARER0, 0, 2, 2);
            run_transaction(9, 128, KEY0, COUNT0, BEARER0, 0, 2, 2);
            run_transaction(10, 4096, KEY0, COUNT0, BEARER0, 0, 2, 2);

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

        i_count = COUNT0;
        i_bearer = BEARER0;
        i_direction = 1'b0;

        i_msg_len = 32'd0;

        i_data = 64'b0;
        i_data_vld = 1'b0;
        i_valid_bytes = 4'd0;

        i_mac_ready = 1'b0;

        error_count = 0;
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
            $display("SNOW3G INT ALL SELECTED TESTS PASS");
        else
            $display(
                "SNOW3G INT FAIL errors=%0d",
                error_count
            );

        $display("======================================");

        $finish;

    end

endmodule