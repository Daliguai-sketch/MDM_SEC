module tb_sec_int_top;

reg clk;
reg rst_n;

initial begin
    clk = 1'b0;
    forever #5 clk = ~clk;
end

reg i_start;
wire o_start_ready;

reg [1:0] i_alg_sel;
reg [127:0] i_key;

reg [31:0] i_count;
reg [4:0] i_bearer;
reg i_direction;

reg [31:0] i_msg_len;

reg [127:0] i_data;
reg i_data_vld;
wire o_data_ready;

reg i_data_last;
reg [4:0] i_valid_bytes;

wire [31:0] o_mac;
wire o_mac_vld;
reg i_mac_ready;

wire o_busy;
wire o_done;

sec_int_top dut (
    .clk(clk),
    .rst_n(rst_n),

    .i_start(i_start),
    .o_start_ready(o_start_ready),

    .i_alg_sel(i_alg_sel),
    .i_key(i_key),

    .i_count(i_count),
    .i_bearer(i_bearer),
    .i_direction(i_direction),

    .i_msg_len(i_msg_len),

    .i_data(i_data),
    .i_data_vld(i_data_vld),
    .o_data_ready(o_data_ready),
    .i_data_last(i_data_last),
    .i_valid_bytes(i_valid_bytes),

    .o_mac(o_mac),
    .o_mac_vld(o_mac_vld),
    .i_mac_ready(i_mac_ready),

    .o_busy(o_busy),
    .o_done(o_done)
);

localparam ALG_AES  = 2'd0;
localparam ALG_SNOW = 2'd1;
localparam ALG_ZUC  = 2'd2;
localparam ALG_NULL = 2'd3;

localparam [127:0] KEY0 =
    128'hF172263558DA301944A74CF383FD23A2;

localparam [127:0] KEY1 =
    128'h000102030405060708090A0B0C0D0E0F;

localparam [31:0] COUNT0 = 32'h36AF6144;
localparam [31:0] COUNT1 = 32'h12345678;

localparam [4:0] BEARER0 = 5'd31;
localparam [4:0] BEARER1 = 5'd7;

integer test_id;
integer current_case;
integer packet_length;
integer block_count;

integer send_index;
integer input_count;
integer mac_count;
integer done_count;
integer error_count;

integer transaction_active;
integer input_bubbles;
integer mac_stalls;

integer timeout_count;
integer remaining;

reg [31:0] golden_mac;
reg [31:0] golden_mem [0:0];
reg [1023:0] golden_file;

reg [31:0] lfsr;

always @(posedge clk or negedge rst_n) begin
    if (!rst_n)
        lfsr <= 32'h13579BDF;
    else
        lfsr <= {
            lfsr[30:0],
            lfsr[31] ^ lfsr[21] ^
            lfsr[1] ^ lfsr[0]
        };
end


function [127:0] make_plain_block;
input integer index;

integer j;
integer value;
reg [127:0] result;

begin
    result = 128'b0;

    for (j = 0; j < 16; j = j + 1) begin
        value = (index * 16 + j) & 255;
        result[127-j*8 -: 8] = value[7:0];
    end

    make_plain_block = result;
end
endfunction


task reset_dut;
begin
    rst_n = 1'b0;

    i_start = 1'b0;
    i_alg_sel = ALG_NULL;
    i_key = 128'b0;

    i_count = 32'b0;
    i_bearer = 5'b0;
    i_direction = 1'b0;
    i_msg_len = 32'b0;

    i_data = 128'b0;
    i_data_vld = 1'b0;
    i_data_last = 1'b0;
    i_valid_bytes = 5'd0;

    i_mac_ready = 1'b0;

    send_index = 0;
    input_count = 0;
    mac_count = 0;
    done_count = 0;
    error_count = 0;

    transaction_active = 0;

    repeat (10) @(negedge clk);
    rst_n = 1'b1;
    repeat (5) @(negedge clk);
end
endtask


task load_golden;
input integer case_id;
begin
    current_case = case_id;

    $sformat(
        golden_file,
        "tb/golden/sec_int/case_%02d.hex",
        case_id
    );

    $readmemh(golden_file, golden_mem);
    golden_mac = golden_mem[0];

    $display(
        "[GOLDEN] CASE=%0d MAC=%08h",
        case_id,
        golden_mac
    );
end
endtask


reg stall_prev;
reg [31:0] stall_mac;

always @(posedge clk) begin

    if (!rst_n) begin
        stall_prev = 1'b0;
        stall_mac = 32'b0;
    end
    else begin

        if (stall_prev) begin
            if (
                o_mac_vld !== 1'b1 ||
                o_mac !== stall_mac
            ) begin
                $display(
                    "[ERROR] MAC changed during stall"
                );
                error_count = error_count + 1;
            end
        end

        stall_prev = o_mac_vld && !i_mac_ready;

        if (stall_prev)
            stall_mac = o_mac;

    end
end


always @(posedge clk) begin

    if (rst_n && transaction_active) begin

        if (i_data_vld && o_data_ready)
            input_count = input_count + 1;

        if (o_mac_vld && i_mac_ready) begin

            mac_count = mac_count + 1;

            if (o_mac !== golden_mac) begin

                $display(
                    "[ERROR] CASE=%0d MAC ACT=%08h EXP=%08h",
                    current_case,
                    o_mac,
                    golden_mac
                );

                error_count = error_count + 1;

            end
        end

        if (o_done)
            done_count = done_count + 1;

    end
end


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
    i_msg_len = length;

    i_start = 1'b1;

    @(negedge clk);
    i_start = 1'b0;
end
endtask


task run_case;

input integer case_id;
input [1:0] alg;
input [127:0] key;
input [31:0] count;
input [4:0] bearer;
input direction;
input integer length;
input integer enable_bubbles;
input integer enable_stalls;

integer local_timeout;
integer next_send;
integer bytes_left;

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
    input_count = 0;
    mac_count = 0;
    done_count = 0;

    transaction_active = 1;

    start_packet(
        alg, key, count, bearer, direction, length
    );

    local_timeout = 0;

    while (
        done_count == 0 &&
        local_timeout < 200000
    ) begin

        @(negedge clk);

        local_timeout = local_timeout + 1;

        if (enable_stalls)
            i_mac_ready = lfsr[3] | lfsr[7];
        else
            i_mac_ready = 1'b1;

        if (!i_data_vld &&
            send_index < block_count) begin

            if (!enable_bubbles ||
                lfsr[2] || lfsr[5]) begin

                i_data = make_plain_block(send_index);

                bytes_left = length - send_index * 16;

                i_data_vld = 1'b1;

                i_data_last =
                    (send_index == block_count - 1);

                if (bytes_left >= 16)
                    i_valid_bytes = 5'd16;
                else
                    i_valid_bytes = bytes_left;
            end
        end

        @(posedge clk);

        if (i_data_vld && o_data_ready) begin
            next_send = send_index + 1;

            #1;
            send_index = next_send;
            i_data_vld = 1'b0;
        end

    end

    @(negedge clk);

    i_data_vld = 1'b0;
    i_mac_ready = 1'b0;

    if (local_timeout >= 200000) begin
        $display("[ERROR] CASE=%0d TIMEOUT", case_id);
        error_count = error_count + 1;
    end

    if (input_count != block_count) begin
        $display(
            "[ERROR] CASE=%0d INPUT COUNT=%0d EXP=%0d",
            case_id,
            input_count,
            block_count
        );
        error_count = error_count + 1;
    end

    if (mac_count != 1) begin
        $display(
            "[ERROR] CASE=%0d MAC COUNT=%0d",
            case_id,
            mac_count
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

    repeat (5) @(negedge clk);

    $display(
        "[END] CASE=%0d MAC=%08h",
        case_id,
        golden_mac
    );

end
endtask


initial begin

    test_id = 0;

    if (!$value$plusargs("TEST=%d", test_id))
        test_id = 0;

    reset_dut();

    case (test_id)

        0: run_case(
            0, ALG_AES, KEY0,
            COUNT0, BEARER0, 1'b0,
            128, 0, 0
        );

        1: run_case(
            1, ALG_SNOW, KEY0,
            COUNT0, BEARER0, 1'b0,
            128, 0, 0
        );

        2: run_case(
            2, ALG_ZUC, KEY0,
            COUNT0, BEARER0, 1'b0,
            128, 0, 0
        );

        3: run_case(
            3, ALG_NULL, KEY0,
            COUNT0, BEARER0, 1'b0,
            128, 0, 0
        );

        4: run_case(
            4, ALG_AES, KEY0,
            COUNT0, BEARER0, 1'b0,
            521, 0, 0
        );

        5: run_case(
            5, ALG_SNOW, KEY0,
            COUNT0, BEARER0, 1'b0,
            513, 1, 0
        );

        6: run_case(
            6, ALG_ZUC, KEY0,
            COUNT0, BEARER0, 1'b0,
            515, 0, 1
        );

        7: begin
            run_case(7, ALG_AES, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     128, 0, 0);

            run_case(8, ALG_SNOW, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     128, 0, 0);

            run_case(9, ALG_ZUC, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     128, 0, 0);

            run_case(10, ALG_NULL, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     128, 0, 0);
        end

        8: begin
            run_case(11, ALG_AES, KEY1,
                     COUNT1, BEARER1, 1'b1,
                     256, 0, 0);

            run_case(12, ALG_AES, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     256, 0, 0);
        end

        9: begin
            run_case(13, ALG_AES, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     0, 0, 0);

            run_case(14, ALG_SNOW, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     0, 0, 0);

            run_case(15, ALG_ZUC, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     0, 0, 0);

            run_case(16, ALG_NULL, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     0, 0, 0);
        end

        10: begin
            run_case(17, ALG_AES, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     4096, 0, 0);

            run_case(18, ALG_SNOW, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     4096, 0, 0);

            run_case(19, ALG_ZUC, KEY0,
                     COUNT0, BEARER0, 1'b0,
                     4096, 0, 0);
        end

        11: run_case(
            20, ALG_ZUC, KEY0,
            COUNT0, BEARER0, 1'b0,
            1024, 1, 1
        );

        default: begin
            $display("[ERROR] Invalid TEST=%0d", test_id);
            error_count = error_count + 1;
        end

    endcase

    if (error_count == 0)
        $display("SEC INT TOP TEST%0d PASS", test_id);
    else
        $display(
            "SEC INT TOP TEST%0d FAIL ERRORS=%0d",
            test_id,
            error_count
        );

    $finish;

end

endmodule