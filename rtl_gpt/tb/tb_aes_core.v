`timescale 1ns/1ps

module tb_aes_core;

reg clk;
reg rst_n;

reg i_start;

reg [127:0] i_key;
reg [127:0] i_data;

wire [127:0] o_data;
wire o_valid;
wire o_busy;

reg [127:0] expected_data;

integer error_count;
integer cycle_count;

// ============================================================
// DUT
// ============================================================

aes_core dut (
    .clk     (clk),
    .rst_n   (rst_n),

    .i_start (i_start),
    .i_key   (i_key),
    .i_data  (i_data),

    .o_data  (o_data),
    .o_valid (o_valid),
    .o_busy  (o_busy)
);

// ============================================================
// Clock
// ============================================================

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

// ============================================================
// Test
// ============================================================

initial begin

    rst_n = 1'b0;
    i_start = 1'b0;

    i_key = 128'd0;
    i_data = 128'd0;

    expected_data = 128'd0;

    error_count = 0;
    cycle_count = 0;

    repeat (5) @(posedge clk);

    @(negedge clk);
    rst_n = 1'b1;

    repeat (3) @(posedge clk);

    // ========================================================
    // AES-128 Standard Vector
    // ========================================================

    @(negedge clk);

    i_key =
        128'h0C0D0E0F08090A0B0405060700010203;

    i_data =
        128'h00112233445566778899AABBCCDDEEFF;

    expected_data =
        128'h69C4E0D86A7B0430D8CDB78070B4C55A;

    i_start = 1'b1;

    @(negedge clk);
    i_start = 1'b0;

    begin : WAIT_AES_RESULT
        for (cycle_count = 0;
             cycle_count < 200;
             cycle_count = cycle_count + 1) begin

            @(negedge clk);

            if (o_valid) begin
                disable WAIT_AES_RESULT;
            end
        end

        $display("ERROR: AES timeout");
        error_count = error_count + 1;
        disable WAIT_AES_RESULT;
    end

    // ========================================================
    // Check
    // ========================================================

    $display("-------------------------------------");
    $display("AES Output  = %032h", o_data);
    $display("AES Expect  = %032h", expected_data);

    if (!o_valid) begin
        $display("AES TEST FAILED: no valid output");
        error_count = error_count + 1;
    end
    else if (o_data == expected_data) begin
        $display("AES TEST PASSED");
    end
    else begin
        $display("AES TEST FAILED");
        error_count = error_count + 1;
    end

    $display("-------------------------------------");

    if (error_count == 0)
        $display("ALL TESTS PASSED");
    else
        $display("TOTAL ERRORS = %0d", error_count);

    #20;
    $finish;

end

endmodule