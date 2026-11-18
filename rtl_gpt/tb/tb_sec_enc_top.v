`timescale 1ns/1ps

module tb_sec_enc_top;

// =========================================================
// Clock / Reset
// =========================================================

reg clk;
reg rst_n;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end


// =========================================================
// DUT Interface
// =========================================================

reg         i_start;
wire        o_start_ready;

reg [1:0]   i_alg_sel;
reg [127:0] i_key;

reg [31:0]  i_count;
reg [4:0]   i_bearer;
reg         i_direction;

reg [31:0]  i_packet_bytes;

reg [127:0] i_data;
reg         i_data_vld;
wire        o_data_ready;

reg         i_data_last;
reg [4:0]   i_valid_bytes;

wire [127:0] o_data;
wire         o_data_vld;
reg          i_data_ready;

wire         o_data_last;
wire [4:0]   o_valid_bytes;

wire o_busy;
wire o_done;


// =========================================================
// DUT
// =========================================================

sec_enc_top dut (
    .clk            (clk),
    .rst_n          (rst_n),

    .i_start        (i_start),
    .o_start_ready  (o_start_ready),

    .i_alg_sel      (i_alg_sel),
    .i_key          (i_key),

    .i_count        (i_count),
    .i_bearer       (i_bearer),
    .i_direction    (i_direction),

    .i_packet_bytes (i_packet_bytes),

    .i_data         (i_data),
    .i_data_vld     (i_data_vld),
    .o_data_ready   (o_data_ready),

    .i_data_last    (i_data_last),
    .i_valid_bytes  (i_valid_bytes),

    .o_data         (o_data),
    .o_data_vld     (o_data_vld),
    .i_data_ready   (i_data_ready),

    .o_data_last    (o_data_last),
    .o_valid_bytes  (o_valid_bytes),

    .o_busy         (o_busy),
    .o_done         (o_done)
);


// =========================================================
// Constants
// =========================================================

localparam ALG_AES  = 2'd0;
localparam ALG_SNOW = 2'd1;
localparam ALG_ZUC  = 2'd2;
localparam ALG_NULL = 2'd3;

localparam [127:0] KEY_AES =
    128'hF172263558DA301944A74CF383FD23A2;

localparam [127:0] KEY_STREAM =
    128'h4881FF48952C491082C5B300ABD6459F;

localparam [127:0] KEY_AES_1 =
    128'h000102030405060708090A0B0C0D0E0F;

localparam [31:0] COUNT0 = 32'h36AF6144;
localparam [31:0] COUNT1 = 32'h12345678;

localparam [4:0] BEARER0 = 5'd31;
localparam [4:0] BEARER1 = 5'd7;

localparam DIR_AES    = 1'b1;
localparam DIR_STREAM = 1'b0;
localparam DIR1       = 1'b0;


// =========================================================
// Test Control
// =========================================================

integer test_id;
integer current_case;

integer packet_length;
integer block_count;

integer send_index;
integer output_index;

integer done_count;
integer error_count;

integer transaction_active;

integer input_bubble_enable;
integer output_stall_enable;

integer expected_last_bytes;

integer timeout_count;

reg [127:0] golden [0:255];
reg [1023:0] golden_file;


// =========================================================
// Deterministic Random Generator
// =========================================================

reg [31:0] lfsr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        lfsr <= 32'h13579BDF;
    else
        lfsr <= {
            lfsr[30:0],
            lfsr[31] ^
            lfsr[21] ^
            lfsr[1] ^
            lfsr[0]
        };
end


// =========================================================
// Plaintext Block Generator
// =========================================================

function [127:0] make_plain_block;

input integer block_index;

integer j;
integer byte_value;
reg [127:0] result;

begin
    result = 128'b0;

    for (j = 0; j < 16; j = j + 1) begin
        byte_value = (block_index * 16 + j) & 255;
        result[127-j*8 -: 8] = byte_value[7:0];
    end

    make_plain_block = result;
end

endfunction


// =========================================================
// Cipher Comparison
// =========================================================

task compare_cipher;

input [127:0] actual;
input [127:0] expected;
input integer valid_bytes;
input integer block_index;

integer j;

begin
    for (j = 0; j < valid_bytes; j = j + 1) begin

        if (
            actual[127-j*8 -: 8] !==
            expected[127-j*8 -: 8]
        ) begin

            $display(
                "[ERROR] CASE=%0d BLOCK=%0d BYTE=%0d ACT=%02X EXP=%02X",
                current_case,
                block_index,
                j,
                actual[127-j*8 -: 8],
                expected[127-j*8 -: 8]
            );

            error_count = error_count + 1;
        end
    end
end

endtask


// =========================================================
// Output Stability Monitor
// =========================================================

reg stall_prev;
reg [127:0] stall_data;
reg stall_last;
reg [4:0] stall_bytes;

always @(posedge clk) begin

    if (!rst_n) begin
        stall_prev = 1'b0;
    end
    else begin

        // Previous cycle stalled: output must remain stable.
        if (stall_prev) begin

            if (
                o_data_vld !== 1'b1 ||
                o_data !== stall_data ||
                o_data_last !== stall_last ||
                o_valid_bytes !== stall_bytes
            ) begin

                $display(
                    "[ERROR] Output stability violation"
                );

                error_count = error_count + 1;
            end
        end

        stall_prev = o_data_vld && !i_data_ready;

        if (stall_prev) begin
            stall_data = o_data;
            stall_last = o_data_last;
            stall_bytes = o_valid_bytes;
        end

    end

end


// =========================================================
// Output Scoreboard
// =========================================================

always @(posedge clk) begin

    if (rst_n && transaction_active) begin

        if (o_data_vld && i_data_ready) begin

            if (output_index >= block_count) begin

                $display(
                    "[ERROR] CASE=%0d Extra output block",
                    current_case
                );

                error_count = error_count + 1;

            end
            else begin

                if (output_index == block_count - 1)
                    expected_last_bytes =
                        packet_length - output_index * 16;
                else
                    expected_last_bytes = 16;

                compare_cipher(
                    o_data,
                    golden[output_index],
                    expected_last_bytes,
                    output_index
                );

                if (
                    o_data_last !==
                    (output_index == block_count - 1)
                ) begin

                    $display(
                        "[ERROR] CASE=%0d BLOCK=%0d LAST mismatch",
                        current_case,
                        output_index
                    );

                    error_count = error_count + 1;
                end

                if (
                    o_valid_bytes !== expected_last_bytes
                ) begin

                    $display(
                        "[ERROR] CASE=%0d BLOCK=%0d VALID_BYTES ACT=%0d EXP=%0d",
                        current_case,
                        output_index,
                        o_valid_bytes,
                        expected_last_bytes
                    );

                    error_count = error_count + 1;
                end

            end

            output_index = output_index + 1;

        end

        if (o_done)
            done_count = done_count + 1;

    end

end


// =========================================================
// Reset Task
// =========================================================

task reset_dut;

begin

    rst_n = 1'b0;

    i_start = 1'b0;

    i_alg_sel = ALG_NULL;
    i_key = 128'b0;

    i_count = 32'b0;
    i_bearer = 5'b0;
    i_direction = 1'b0;

    i_packet_bytes = 32'b0;

    i_data = 128'b0;
    i_data_vld = 1'b0;
    i_data_last = 1'b0;
    i_valid_bytes = 5'b0;

    i_data_ready = 1'b0;

    transaction_active = 0;

    error_count = 0;
    done_count = 0;

    output_index = 0;
    send_index = 0;

    stall_prev = 1'b0;

    repeat (10)
        @(negedge clk);

    rst_n = 1'b1;

    repeat (5)
        @(negedge clk);

end

endtask


// =========================================================
// Load Golden
// =========================================================

task load_golden;

input integer case_id;

begin

    current_case = case_id;

    $sformat(
        golden_file,
        "tb/golden/sec_enc/case_%02d.hex",
        case_id
    );

    $readmemh(
        golden_file,
        golden
    );

end

endtask


// =========================================================
// Start Transaction
// =========================================================

task start_packet;

input [1:0] alg;
input [127:0] key;

input [31:0] count;
input [4:0] bearer;
input direction;

input integer length;

begin

    @(negedge clk);

    while (!o_start_ready)
        @(negedge clk);

    i_alg_sel = alg;
    i_key = key;

    i_count = count;
    i_bearer = bearer;
    i_direction = direction;

    i_packet_bytes = length;

    i_start = 1'b1;

    @(negedge clk);

    i_start = 1'b0;

end

endtask


// =========================================================
// Run Case
// =========================================================

task run_case;

input integer case_id;

input [1:0] alg;
input [127:0] key;

input [31:0] count;
input [4:0] bearer;
input direction;

input integer length;

input integer input_bubbles;
input integer output_stalls;

integer remaining;
integer next_send_index;
integer local_timeout;

begin

    $display(
        "[RUN] CASE=%0d ALG=%0d BYTES=%0d",
        case_id,
        alg,
        length
    );

    load_golden(case_id);

    packet_length = length;
    block_count = (length + 15) / 16;

    send_index = 0;
    output_index = 0;

    done_count = 0;

    input_bubble_enable = input_bubbles;
    output_stall_enable = output_stalls;

    transaction_active = 1;

    start_packet(
        alg,
        key,
        count,
        bearer,
        direction,
        length
    );

    local_timeout = 0;

    // =====================================================
    // Transaction Loop
    // =====================================================

    while (
        done_count == 0 &&
        local_timeout < 200000
    ) begin

        @(negedge clk);

        local_timeout = local_timeout + 1;

        // ---------------------------------------------
        // Output Ready
        // ---------------------------------------------

        if (output_stall_enable)
            i_data_ready = lfsr[3] | lfsr[7];
        else
            i_data_ready = 1'b1;

        // ---------------------------------------------
        // Input Valid
        // ---------------------------------------------

        if (!i_data_vld && send_index < block_count) begin

            if (
                !input_bubble_enable ||
                lfsr[2] ||
                lfsr[5]
            ) begin

                i_data =
                    make_plain_block(send_index);

                remaining =
                    packet_length - send_index * 16;

                i_data_vld = 1'b1;

                i_data_last =
                    (send_index == block_count - 1);

                if (remaining >= 16)
                    i_valid_bytes = 5'd16;
                else
                    i_valid_bytes = remaining;

            end

        end

        // ---------------------------------------------
        // Input Handshake
        // ---------------------------------------------

        @(posedge clk);

        if (i_data_vld && o_data_ready) begin

            next_send_index = send_index + 1;

            #1;

            send_index = next_send_index;
            i_data_vld = 1'b0;

        end

    end

    @(negedge clk);

    i_data_vld = 1'b0;
    i_data_ready = 1'b0;

    if (local_timeout >= 200000) begin

        $display(
            "[ERROR] CASE=%0d TIMEOUT",
            case_id
        );

        error_count = error_count + 1;
    end

    if (output_index != block_count) begin

        $display(
            "[ERROR] CASE=%0d OUTPUT COUNT=%0d EXPECTED=%0d",
            case_id,
            output_index,
            block_count
        );

        error_count = error_count + 1;
    end

    if (done_count != 1) begin

        $display(
            "[ERROR] CASE=%0d DONE COUNT=%0d",
            case_id,
            done_count
        );

        error_count = error_count + 1;
    end

    transaction_active = 0;

    repeat (5)
        @(negedge clk);

    $display(
        "[END] CASE=%0d BLOCKS=%0d",
        case_id,
        output_index
    );

end

endtask


// =========================================================
// Main
// =========================================================

initial begin

    test_id = 0;

    if (!$value$plusargs("TEST=%d", test_id))
        test_id = 0;

    reset_dut();

    case (test_id)

        // TEST0: AES 128B
        0: begin
            run_case(
                0, ALG_AES, KEY_AES,
                COUNT0, BEARER0, DIR_AES,
                128, 0, 0
            );
        end

        // TEST1: SNOW3G 128B
        1: begin
            run_case(
                1, ALG_SNOW, KEY_STREAM,
                COUNT0, BEARER0, DIR_STREAM,
                128, 0, 0
            );
        end

        // TEST2: ZUC 128B
        2: begin
            run_case(
                2, ALG_ZUC, KEY_STREAM,
                COUNT0, BEARER0, DIR_STREAM,
                128, 0, 0
            );
        end

        // TEST3: NULL 128B
        3: begin
            run_case(
                3, ALG_NULL, KEY_AES,
                COUNT0, BEARER0, DIR_AES,
                128, 0, 0
            );
        end

        // TEST4: AES 508B
        4: begin
            run_case(
                4, ALG_AES, KEY_AES,
                COUNT0, BEARER0, DIR_AES,
                508, 0, 0
            );
        end

        // TEST5: SNOW3G Input Bubbles
        5: begin
            run_case(
                5, ALG_SNOW, KEY_STREAM,
                COUNT0, BEARER0, DIR_STREAM,
                512, 1, 0
            );
        end

        // TEST6: ZUC Output Backpressure
        6: begin
            run_case(
                6, ALG_ZUC, KEY_STREAM,
                COUNT0, BEARER0, DIR_STREAM,
                512, 0, 1
            );
        end

        // TEST7: Algorithm Switching
        7: begin

            run_case(
                7, ALG_AES, KEY_AES,
                COUNT0, BEARER0, DIR_AES,
                128, 0, 0
            );

            run_case(
                8, ALG_SNOW, KEY_STREAM,
                COUNT0, BEARER0, DIR_STREAM,
                128, 0, 0
            );

            run_case(
                9, ALG_ZUC, KEY_STREAM,
                COUNT0, BEARER0, DIR_STREAM,
                128, 0, 0
            );

            run_case(
                10, ALG_NULL, KEY_AES,
                COUNT0, BEARER0, DIR_AES,
                128, 0, 0
            );

        end

        // TEST8: AES Key / COUNT Update
        8: begin

            run_case(
                11, ALG_AES, KEY_AES_1,
                COUNT1, BEARER1, DIR1,
                256, 0, 0
            );

            run_case(
                12, ALG_AES, KEY_AES,
                COUNT0, BEARER0, DIR_AES,
                256, 0, 0
            );

        end

        // TEST9: Zero Byte
        9: begin
            run_case(
                13, ALG_NULL, KEY_AES,
                COUNT0, BEARER0, DIR_AES,
                0, 0, 0
            );
        end

        // TEST10: 4096 Byte
        10: begin

            run_case(
                14, ALG_AES, KEY_AES,
                COUNT0, BEARER0, DIR_AES,
                4096, 0, 0
            );

            run_case(
                15, ALG_SNOW, KEY_STREAM,
                COUNT0, BEARER0, DIR_STREAM,
                4096, 0, 0
            );

            run_case(
                16, ALG_ZUC, KEY_STREAM,
                COUNT0, BEARER0, DIR_STREAM,
                4096, 0, 0
            );

        end

        // TEST11: Valid/Ready Stability
        11: begin
            run_case(
                17, ALG_ZUC, KEY_STREAM,
                COUNT0, BEARER0, DIR_STREAM,
                1024, 1, 1
            );
        end

        default: begin
            $display(
                "[ERROR] Invalid TEST=%0d",
                test_id
            );
            error_count = error_count + 1;
        end

    endcase

    if (error_count == 0) begin

        $display(
            "========================================"
        );
        $display(
            "SEC ENC TOP TEST%0d PASS",
            test_id
        );
        $display(
            "========================================"
        );

    end
    else begin

        $display(
            "========================================"
        );
        $display(
            "SEC ENC TOP TEST%0d FAIL ERRORS=%0d",
            test_id,
            error_count
        );
        $display(
            "========================================"
        );

    end

    $finish;

end

endmodule