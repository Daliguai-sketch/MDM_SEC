`timescale 1ns/1ps

module tb_aes_ctr_top;

reg clk;
reg rst_n;

// ============================================================
// Key Interface
// ============================================================

reg          i_key_load;
wire         o_key_load_ready;

reg  [127:0] i_key;
wire         o_key_ready;

// ============================================================
// CTR Interface
// ============================================================

reg          i_ctr_init;
wire         o_ctr_init_ready;

reg  [31:0]  i_count;
reg  [4:0]   i_bearer;
reg          i_direction;

// ============================================================
// Stream Interface
// ============================================================

reg          i_stream_vld;
wire         o_stream_ready;

wire [127:0] o_stream;
wire         o_stream_vld;

reg          i_stream_ready;

// ============================================================
// DUT
// ============================================================

aes_ctr_top dut (
    .clk              (clk),
    .rst_n            (rst_n),

    .i_key_load       (i_key_load),
    .o_key_load_ready (o_key_load_ready),
    .i_key            (i_key),
    .o_key_ready      (o_key_ready),

    .i_ctr_init       (i_ctr_init),
    .o_ctr_init_ready (o_ctr_init_ready),

    .i_count          (i_count),
    .i_bearer         (i_bearer),
    .i_direction      (i_direction),

    .i_stream_vld     (i_stream_vld),
    .o_stream_ready   (o_stream_ready),

    .o_stream         (o_stream),
    .o_stream_vld     (o_stream_vld),
    .i_stream_ready   (i_stream_ready)
);

// ============================================================
// Clock
// ============================================================

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

// ============================================================
// Cycle Counter
// ============================================================

integer cycle_count;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        cycle_count <= 0;
    else
        cycle_count <= cycle_count + 1;
end

// ============================================================
// Expected Stream Storage
// ============================================================

reg [127:0] expected_stream [0:31];

integer request_count;
integer output_count;
integer error_count;

integer request_cycle [0:31];

// ============================================================
// Key Load Task
// ============================================================

task load_key;

    input [127:0] key;

    begin

        @(negedge clk);

        i_key = key;
        i_key_load = 1'b1;

        while (!o_key_load_ready)
            @(negedge clk);

        @(negedge clk);
        i_key_load = 1'b0;

        while (!o_key_ready)
            @(negedge clk);

        $display("[TB] AES Key Ready");

    end

endtask

// ============================================================
// CTR Init Task
// ============================================================

task init_ctr;

    input [31:0] count;
    input [4:0]  bearer;
    input        direction;

    begin

        @(negedge clk);

        i_count = count;
        i_bearer = bearer;
        i_direction = direction;

        i_ctr_init = 1'b1;

        while (!o_ctr_init_ready)
            @(negedge clk);

        @(negedge clk);
        i_ctr_init = 1'b0;

        $display("[TB] CTR Initialized");

    end

endtask

// ============================================================
// Send Stream Request
// ============================================================

task send_request;

    begin

        @(negedge clk);

        i_stream_vld = 1'b1;

        while (!o_stream_ready)
            @(negedge clk);

        @(negedge clk);

        i_stream_vld = 1'b0;

        $display(
            "[TB] Stream Request Accepted at cycle %0d",
            cycle_count
        );

    end

endtask

// ============================================================
// Stream Output Monitor
// ============================================================

always @(posedge clk) begin

    if (rst_n) begin

        if (i_stream_vld && o_stream_ready) begin

            request_cycle[request_count] = cycle_count;

            request_count = request_count + 1;

        end

        if (o_stream_vld && i_stream_ready) begin

            $display(
                "[TB] Stream %0d = %032h at cycle %0d",
                output_count,
                o_stream,
                cycle_count
            );

            if (o_stream !== expected_stream[output_count]) begin

                $display(
                    "[ERROR] Expected = %032h",
                    expected_stream[output_count]
                );

                error_count = error_count + 1;

            end

            output_count = output_count + 1;

        end

    end

end

// ============================================================
// Main Test
// ============================================================

initial begin

    rst_n = 1'b0;

    i_key_load = 1'b0;
    i_key = 128'd0;

    i_ctr_init = 1'b0;

    i_count = 32'd0;
    i_bearer = 5'd0;
    i_direction = 1'b0;

    i_stream_vld = 1'b0;
    i_stream_ready = 1'b1;

    request_count = 0;
    output_count = 0;
    error_count = 0;

    repeat (5)
        @(negedge clk);

    rst_n = 1'b1;

    // ========================================================
    // Test Key
    // ========================================================

    load_key(
        128'h4881FF48952C491082C5B300ABD6459F
    );

    // ========================================================
    // CTR Configuration
    // ========================================================

    init_ctr(
        32'h36AF6144,
        5'h1F,
        1'b0
    );

    // ========================================================
    // Golden Streams
    // ========================================================

    // These must be generated using Python Golden Model.
    //
    // expected_stream[0] = 
    // expected_stream[1] = ...
    // expected_stream[2] = ...
    expected_stream[0] = 128'h120B44EBF85A03123556250319DBDC6D;
    expected_stream[1] = 128'hB1CF309381F05D8FB45CC70AA0DD82BC;
    expected_stream[2] = 128'h50495E0AABF070A9C8CC33CD7E50C124;
    expected_stream[3] = 128'h665C4491640C3135EDFE0C5A5F25733D;
    expected_stream[4] = 128'h1EACC8ADA55006114FDBB476D6ABDCB4;
    expected_stream[5] = 128'hA3685C0F46945CF9AC261C983BEA6C39;

    // ========================================================
    // Test 1: Continuous Requests
    // ========================================================

    $display("========== TEST 1 ==========");

    send_request();
    send_request();
    send_request();

    // Wait all outputs

    wait(output_count == 3);

    // ========================================================
    // Test 2: Non-continuous Requests
    // ========================================================

    $display("========== TEST 2 ==========");

    repeat (7)
        @(negedge clk);

    send_request();

    repeat (13)
        @(negedge clk);

    send_request();

    wait(output_count == 5);

    // ========================================================
    // Test 3: Output Backpressure
    // ========================================================

    $display("========== TEST 3 ==========");

    i_stream_ready = 1'b0;

    send_request();

    repeat (10)
        @(negedge clk);

    if (!o_stream_vld) begin
        $display("[ERROR] Output valid missing");
        error_count = error_count + 1;
    end

    i_stream_ready = 1'b1;

    wait(output_count == 6);

    // ========================================================
    // Test Complete
    // ========================================================

    repeat (10)
        @(negedge clk);

    if (error_count == 0)
        $display("ALL AES CTR TESTS PASSED");
    else
        $display("AES CTR TEST FAILED: %0d errors", error_count);

    $finish;

end

// ============================================================
// Timeout Protection
// ============================================================

initial begin

    #100000;

    $display("[ERROR] Simulation Timeout");

    $finish;

end

endmodule
