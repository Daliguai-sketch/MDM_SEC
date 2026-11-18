
module tb_aes_cmac_top;

parameter CLK_PERIOD = 10;

localparam [127:0] KEY0 =
    128'hF172263558DA301944A74CF383FD23A2;

localparam [127:0] KEY1 =
    128'h000102030405060708090A0B0C0D0E0F;

localparam [31:0] COUNT0 = 32'h36AF6144;

reg clk;
reg rst_n;

initial begin
    clk = 1'b0;
    forever #(CLK_PERIOD/2) clk = ~clk;
end

// ============================================================
// DUT Interface
// ============================================================

reg          i_key_load;
wire         o_key_load_ready;
reg [127:0]  i_int_key;
wire         o_key_ready;

reg          i_mac_start;
wire         o_mac_start_ready;

reg [31:0]   i_count;
reg [4:0]    i_bearer;
reg          i_direction;

reg [127:0]  i_data;
reg          i_data_vld;
wire         o_data_ready;
reg          i_data_last;
reg [4:0]    i_valid_bytes;

wire [31:0]  o_mac;
wire         o_mac_vld;
reg          i_mac_ready;

// ============================================================
// DUT
// ============================================================

aes_cmac_top dut (
    .clk                (clk),
    .rst_n              (rst_n),

    .i_key_load         (i_key_load),
    .o_key_load_ready   (o_key_load_ready),
    .i_int_key          (i_int_key),
    .o_key_ready        (o_key_ready),

    .i_mac_start        (i_mac_start),
    .o_mac_start_ready  (o_mac_start_ready),

    .i_count            (i_count),
    .i_bearer           (i_bearer),
    .i_direction        (i_direction),

    .i_data             (i_data),
    .i_data_vld         (i_data_vld),
    .o_data_ready       (o_data_ready),
    .i_data_last        (i_data_last),
    .i_valid_bytes      (i_valid_bytes),

    .o_mac              (o_mac),
    .o_mac_vld          (o_mac_vld),
    .i_mac_ready        (i_mac_ready)
);

initial begin                                           
    $display("[TB] Start FSDB dump at time %0t", $time);
    $fsdbDumpfile("waves.fsdb");                        
    $fsdbDumpvars(0,tb_aes_cmac_top);                   
    $display("[TB] FSDB dump setup done");              
end                                                     

// ============================================================
// Golden Storage
// ============================================================

reg [31:0] golden_mac [0:63];

initial begin
    $readmemh(
        "tb/golden/aes_cmac_golden.hex",
        golden_mac
    );
end

// ============================================================
// Counters
// ============================================================

integer cycle_count;
integer error_count;
integer test_error_count;
integer current_test;

integer aes_block_count;
integer last_aes_cycle;
integer interval_error_count;

integer test_select;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cycle_count <= 0;
    else
        cycle_count <= cycle_count + 1;
end

// ============================================================
// Reset
// ============================================================

task reset_dut;
begin
    @(negedge clk);

    rst_n = 0;

    i_key_load = 0;
    i_int_key = 0;

    i_mac_start = 0;

    i_count = COUNT0;
    i_bearer = 5'h1F;
    i_direction = 0;

    i_data = 0;
    i_data_vld = 0;
    i_data_last = 0;
    i_valid_bytes = 0;

    i_mac_ready = 0;

    repeat (5)
        @(negedge clk);

    rst_n = 1;

    repeat (2)
        @(negedge clk);
end
endtask

// ============================================================
// Input Generator
// ============================================================

function [127:0] gen_input_word;
    input integer start_byte;
    input integer valid_bytes;

    integer j;
    reg [127:0] tmp;
begin
    tmp = 128'd0;

    for (j=0; j<16; j=j+1)
        if (j < valid_bytes)
            tmp[127-j*8 -: 8] =
                (start_byte+j) & 8'hFF;

    gen_input_word = tmp;
end
endfunction

// ============================================================
// Key Load
// ============================================================

task load_key;
    input [127:0] key;
begin
    @(negedge clk);

    i_int_key = key;
    i_key_load = 1;

    while (!o_key_load_ready)
        @(negedge clk);

    @(negedge clk);
    i_key_load = 0;

    while (!o_key_ready)
        @(negedge clk);
end
endtask

// ============================================================
// MAC Start
// ============================================================

task start_mac;
    input [31:0] count;
begin
    @(negedge clk);

    i_count = count;
    i_mac_start = 1;

    while (!o_mac_start_ready)
        @(negedge clk);

    @(negedge clk);
    i_mac_start = 0;
end
endtask

// ============================================================
// Send Beat
// ============================================================

task send_beat;
    input [127:0] data;
    input [4:0] bytes;
    input last;
    input integer gap;
begin
    repeat (gap)
        @(negedge clk);

    @(negedge clk);

    i_data = data;
    i_valid_bytes = bytes;
    i_data_last = last;
    i_data_vld = 1;

    while (!o_data_ready)
        @(negedge clk);

    @(negedge clk);

    i_data_vld = 0;
    i_data_last = 0;
end
endtask

// ============================================================
// Send Message
// ============================================================

task send_message;
    input integer length;
    input integer random_gap;

    integer sent;
    integer bytes;
    integer gap;
    reg [127:0] word;
begin
    sent = 0;

    if (length == 0) begin
        send_beat(128'd0, 5'd0, 1'b1, 0);
    end
    else begin
        while (sent < length) begin

            bytes = ((length-sent) >= 16)
                ? 16 : (length-sent);

            word = gen_input_word(sent, bytes);

            gap = random_gap
                ? (($random & 32'h7fffffff) % 8)
                : 0;

            send_beat(
                word,
                bytes[4:0],
                (sent+bytes == length),
                gap
            );

            sent = sent + bytes;
        end
    end
end
endtask

// ============================================================
// Check MAC
// ============================================================

task check_mac;
    input [31:0] expected;
    input integer stall_cycles;

    integer k;
    reg [31:0] held_mac;
begin
    i_mac_ready = 0;

    while (!o_mac_vld)
        @(negedge clk);

    held_mac = o_mac;

    if (o_mac !== expected) begin
        $display(
            "[FAIL] TEST=%0d MAC=%08h EXPECT=%08h",
            current_test, o_mac, expected
        );
        test_error_count = test_error_count + 1;
    end
    else begin
        $display(
            "[PASS] TEST=%0d MAC=%08h",
            current_test, o_mac
        );
    end

    for (k=0; k<stall_cycles; k=k+1) begin
        @(negedge clk);

        if (!o_mac_vld || o_mac !== held_mac) begin
            $display("[FAIL] MAC unstable under stall");
            test_error_count = test_error_count + 1;
        end
    end

    @(negedge clk);
    i_mac_ready = 1;

    @(negedge clk);
    i_mac_ready = 0;
end
endtask

// ============================================================
// Run Message
// ============================================================

task run_message;
    input integer length;
    input [31:0] count;
    input [31:0] expected;
    input integer random_gap;
    input integer stall_cycles;
begin
    start_mac(count);
    send_message(length, random_gap);
    check_mac(expected, stall_cycles);
end
endtask

// ============================================================
// TEST 0: BASIC
// ============================================================

task test0_basic;
    integer i;
    integer lengths [0:12];
begin
    current_test = 0;
    test_error_count = 0;

    reset_dut();
    load_key(KEY0);

    lengths[0] = 0;
    lengths[1] = 1;
    lengths[2] = 7;
    lengths[3] = 8;
    lengths[4] = 9;
    lengths[5] = 15;
    lengths[6] = 16;
    lengths[7] = 17;
    lengths[8] = 24;
    lengths[9] = 32;
    lengths[10] = 64;
    lengths[11] = 128;
    lengths[12] = 4096;

    for (i=0; i<13; i=i+1)
        run_message(lengths[i], COUNT0,
                    golden_mac[i], 0, 0);

    report_test();
end
endtask

// ============================================================
// TEST 1: THROUGHPUT
// ============================================================

task test1_throughput;
begin
    current_test = 1;
    test_error_count = 0;

    reset_dut();
    load_key(KEY0);

    interval_error_count = 0;

    aes_block_count = 0;
    last_aes_cycle = 0;
    interval_error_count = 0;

    run_message(4096, COUNT0, golden_mac[12], 0, 0);

    if (interval_error_count != 0) begin
        $display(
            "[FAIL] THROUGHPUT ERRORS=%0d",
            interval_error_count
        );
        test_error_count = test_error_count + 1;
    end

    report_test();
end
endtask

// ============================================================
// TEST 2: RANDOM GAP
// ============================================================

task test2_random_gap;
begin
    current_test = 2;
    test_error_count = 0;

    reset_dut();
    load_key(KEY0);

    run_message(4096, COUNT0, golden_mac[12], 1, 0);

    report_test();
end
endtask

// ============================================================
// TEST 3: BACKPRESSURE
// ============================================================

task test3_backpressure;
begin
    current_test = 3;
    test_error_count = 0;

    reset_dut();
    load_key(KEY0);

    run_message(128, COUNT0, golden_mac[11], 0, 20);

    report_test();
end
endtask

// ============================================================
// TEST 4: MULTI MESSAGE
// ============================================================

task test4_multi_message;
begin
    current_test = 4;
    test_error_count = 0;

    reset_dut();
    load_key(KEY0);

    run_message(128, 32'h36AF6144, golden_mac[13], 0, 0);
    run_message(4096,32'h36AF6145, golden_mac[14], 0, 0);
    run_message(24,  32'h36AF6146, golden_mac[15], 0, 0);
    run_message(0,   32'h36AF6147, golden_mac[16], 0, 0);

    report_test();
end
endtask

// ============================================================
// TEST 5: KEY UPDATE
// ============================================================

task test5_key_update;
begin
    current_test = 5;
    test_error_count = 0;

    reset_dut();

    load_key(KEY0);
    run_message(128, COUNT0, golden_mac[17], 0, 0);

    load_key(KEY1);
    run_message(128, COUNT0, golden_mac[18], 0, 0);

    report_test();
end
endtask

// ============================================================
// TEST 6: KEY SWITCH BACK
// ============================================================

task test6_key_switch_back;
begin
    current_test = 6;
    test_error_count = 0;

    reset_dut();

    load_key(KEY0);
    run_message(128, COUNT0, golden_mac[19], 0, 0);

    load_key(KEY1);
    run_message(128, COUNT0, golden_mac[20], 0, 0);

    load_key(KEY0);
    run_message(128, COUNT0, golden_mac[21], 0, 0);

    report_test();
end
endtask

// ============================================================
// TEST 7: READY/VALID
// ============================================================

task test7_ready_valid;
begin
    current_test = 7;
    test_error_count = 0;

    reset_dut();
    load_key(KEY0);

    run_message(4096, COUNT0, golden_mac[12], 1, 30);

    report_test();
end
endtask

// ============================================================
// Report
// ============================================================

task report_test;
begin
    if (test_error_count == 0)
        $display("[TEST %0d] PASS", current_test);
    else
        $display(
            "[TEST %0d] FAIL ERRORS=%0d",
            current_test, test_error_count
        );

    error_count = error_count + test_error_count;
end
endtask

// ============================================================
// Throughput Monitor
// ============================================================

always @(posedge clk) begin
    if (rst_n &&
        current_test == 1 &&
        dut.ctrl_aes_block_valid &&
        dut.ctrl_aes_block_ready) begin

        if (aes_block_count > 0) begin
            if ((cycle_count-last_aes_cycle) != 5)
                interval_error_count =
                    interval_error_count + 1;
        end

        last_aes_cycle = cycle_count;
        aes_block_count = aes_block_count + 1;
    end
end

// ============================================================
// Main
// ============================================================

initial begin
    rst_n = 0;

    i_key_load = 0;
    i_mac_start = 0;
    i_data_vld = 0;
    i_mac_ready = 0;

    error_count = 0;
    current_test = -1;

    aes_block_count = 0;
    last_aes_cycle = 0;
    interval_error_count = 0;

    if (!$value$plusargs("TEST=%d", test_select))
        test_select = -1;

    case (test_select)
        0: test0_basic();
        1: test1_throughput();
        2: test2_random_gap();
        3: test3_backpressure();
        4: test4_multi_message();
        5: test5_key_update();
        6: test6_key_switch_back();
        7: test7_ready_valid();

        default: begin
            test0_basic();
            test1_throughput();
            test2_random_gap();
            test3_backpressure();
            test4_multi_message();
            test5_key_update();
            test6_key_switch_back();
            test7_ready_valid();
        end
    endcase

    if (error_count == 0)
        $display("ALL SELECTED TESTS PASSED");
    else
        $display("TOTAL ERRORS=%0d", error_count);

    $finish;
end

// ============================================================
// Timeout
// ============================================================

initial begin
    #2000000;
    $display("[FAIL] SIMULATION TIMEOUT");
    $finish;
end

endmodule