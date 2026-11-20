// Packet-level modem security block with 128-bit data ports.
// See docs/rtl_interface.md for the segmented input and output protocol.
module mdm_sec #(
    parameter integer MAX_BYTES = 2048,
    parameter integer AES_LOW_AREA = 1
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         cmd_valid,
    output wire         cmd_ready,
    input  wire [2:0]   cmd_mode,
    input  wire [1:0]   cmd_cipher_alg,
    input  wire [1:0]   cmd_int_alg,
    input  wire [127:0] cmd_cipher_key,
    input  wire [127:0] cmd_int_key,
    input  wire [31:0]  cmd_count,
    input  wire [4:0]   cmd_bearer,
    input  wire         cmd_direction,
    input  wire [15:0]  cmd_a_bytes,
    input  wire [15:0]  cmd_b_bytes,
    input  wire         in_valid,
    output wire         in_ready,
    input  wire [127:0] in_data,
    output wire         rsp_valid,
    input  wire         rsp_ready,
    output wire [31:0]  rsp_mac,
    output wire         rsp_mac_valid,
    output wire [15:0]  rsp_cipher_bytes,
    output wire         rsp_error,
    output wire         cipher_valid,
    input  wire         cipher_ready,
    output reg  [127:0] cipher_data,
    output wire [15:0]  cipher_keep,
    output wire         cipher_last,
    output wire [31:0]  rsp_rx_mac,
    output wire         rsp_rx_mac_valid,
    output wire         rsp_mac_match
);
    // Reject invalid buffer parameters during simulation/elaboration.
    generate
        if (MAX_BYTES < 1 || MAX_BYTES > 65535) begin: g_invalid_max_bytes
            initial begin
                $display("ERROR: MAX_BYTES must be in 1..65535");
                $finish;
            end
        end
    endgenerate
    localparam [2:0] IDLE=0, LOAD_A=1, LOAD_B=2, RUN=3, RESPONSE=4, OUTPUT=5;
    localparam [15:0] MAX_BYTES_16 = MAX_BYTES[15:0];
    // One buffer holds A, B and (for mode 2) up to four appended MAC bytes.
    // At the 16-bit address limit the append wraps into A only after A has
    // been authenticated; a full 65536-byte ring makes that wrap explicit.
    localparam integer BUFFER_CAP = (MAX_BYTES>65532) ? 65536 : MAX_BYTES+4;
    reg [2:0] state, next_state;
    reg [2:0] mode_q;
    reg [1:0] enc_alg_q,int_alg_q;
    reg [127:0] enc_key_q,int_key_q;
    reg [31:0] count_q;
    reg [4:0] bearer_q;
    reg direction_q;
    reg [15:0] a_len,b_len,total_len,cipher_len;
    reg [15:0] load_pos,enc_pos,int_pos,out_pos;
    reg [31:0] mac_q,rx_mac_q;
    reg mac_valid_q,rx_mac_valid_q,error_q;
    reg enc_started,int_started,enc_finished,int_finished;

    // Explicit overflow checks keep all byte lengths/counters 16 bits.
    wire [15:0] cmd_total = cmd_a_bytes+cmd_b_bytes;
    wire cmd_add_overflow = cmd_total<cmd_a_bytes;
    wire cmd_mac_overflow = (cmd_mode==3'd2) && (cmd_b_bytes>16'hfffb);
    wire cmd_capacity_overflow;
    generate
        if (MAX_BYTES<65535) begin: g_check_capacity
            assign cmd_capacity_overflow = (cmd_total>MAX_BYTES_16);
        end else begin: g_full_capacity
            assign cmd_capacity_overflow = 1'b0;
        end
    endgenerate
    wire cmd_short_tag = (cmd_mode==3'd5) && (cmd_b_bytes<16'd4);
    wire cmd_bad = (cmd_mode>3'd5) || cmd_add_overflow ||
                   cmd_capacity_overflow || cmd_mac_overflow || cmd_short_tag;
    // Mode 5 decrypts all B bytes but only emits/authenticates B minus MAC.
    // The subtraction is used only for accepted commands, which have B>=4.
    wire [15:0] enc_len = (mode_q==3'd5) ? b_len : cipher_len;
    wire [15:0] int_len = (mode_q==3'd5) ? total_len-16'd4 : total_len;
    wire [15:0] load_left = (state==LOAD_A) ? a_len-load_pos : total_len-load_pos;
    wire [15:0] load_n = (load_left>=16'd16) ? 16'd16 : load_left;
    wire [15:0] out_left = cipher_len-out_pos;
    wire [15:0] out_n = (out_left>=16'd16) ? 16'd16 : out_left;
    wire enc_enable = (mode_q!=3'd1);
    wire int_enable = (mode_q!=3'd0);
    // Start both requested lanes on the same edge; dependencies stall only
    // the affected input words rather than serializing the whole packet.
    wire enc_start = (state==RUN) && enc_enable && !enc_started;
    wire int_start = (state==RUN) && int_enable && !int_started;
    wire int_after_cipher = (mode_q==3'd3 || mode_q==3'd5);
    wire [15:0] enc_left = (enc_pos<enc_len) ? enc_len-enc_pos : 16'b0;
    wire [15:0] enc_b_left = (enc_pos<b_len) ? b_len-enc_pos : 16'b0;
    wire [15:0] int_left = (int_pos<int_len) ? int_len-int_pos : 16'b0;
    wire [15:0] enc_chunk = (enc_left>=16'd4) ? 16'd4 : enc_left;
    wire [15:0] int_chunk = (int_left>=16'd4) ? 16'd4 : int_left;
    wire [15:0] int_end = int_pos+int_chunk;
    wire [15:0] result_needed = (int_end>a_len) ? int_end-a_len : 16'b0;
    wire enc_in_ready,int_in_ready,enc_out_valid,enc_done,int_done;
    wire [31:0] enc_out,calculated_mac;
    wire [15:0] enc_out_bytes;
    // Modes 3/5 consume produced bytes only on a later edge. This prevents
    // integrity from reading ciphertext/plaintext before it is written.
    wire int_dep_ready = !int_after_cipher || (enc_pos>=result_needed);
    wire int_in_valid = (state==RUN) && int_started && !int_finished &&
                        (int_alg_q!=2'd0) && (int_pos<int_len) && int_dep_ready;
    wire int_take = int_in_valid && int_in_ready;

    // In modes 2/4 integrity needs original B, whereas cipher overwrites B
    // in place. Allow a write only after all its original B bytes have been
    // read by integrity, including an integrity transfer on this same edge.
    // RAM reads are asynchronous and the consuming registers sample old data
    // at that edge, before the nonblocking memory write becomes visible.
    wire [15:0] enc_end = enc_pos+enc_chunk;
    wire [15:0] old_b_end = (enc_end<b_len) ? enc_end : b_len;
    wire [15:0] old_input_end = a_len+old_b_end;
    wire [15:0] int_read_end = int_take ? int_end : int_pos;
    wire enc_mem_ready = (mode_q!=3'd2 && mode_q!=3'd4) ||
                         (enc_pos>=b_len) || (int_alg_q==2'd0) ||
                         int_finished || (old_input_end<=int_read_end);
    // A mode-2 word containing any appended MAC bytes waits for the MAC.
    wire enc_mac_ready = (mode_q!=3'd2) || (enc_chunk<=enc_b_left) || int_finished;
    wire enc_dep_ready = enc_mem_ready && enc_mac_ready;
    wire enc_in_valid = (state==RUN) && enc_started && !enc_finished &&
                        (enc_pos<enc_len) && enc_dep_ready;

    // Input is loaded first; in RUN each cipher result replaces its own B
    // bytes. The interface never loads and computes on the same edge.
    wire result_wr_en = (state==RUN) && enc_out_valid;
    wire [15:0] input_wr_addr = result_wr_en ? a_len+enc_pos : load_pos;
    wire [15:0] input_wr_bytes = result_wr_en ? enc_out_bytes : load_n;
    wire [127:0] input_wr_data = result_wr_en ? {enc_out,96'b0} : in_data;
    wire [15:0] input_rd0_addr = a_len+((state==OUTPUT) ? out_pos : enc_pos);
    wire [127:0] input_rd0;
    wire [31:0] input_rd1;
    // The trailing four decrypted bytes are collected as cipher words arrive.
    wire capture_rx_mac = (state==RUN) && (mode_q==3'd5) && enc_done;

    // One 16-bank packet buffer replaces the previous input + result copies.
    // Its two asynchronous reads feed cipher and integrity concurrently;
    // rd0 supplies the 128-bit output once all processing is complete.
    mdm_packet_buffer #(.CAP_BYTES(BUFFER_CAP),.READ_PORTS(2)) u_input_buffer (
        .clk(clk), .wr_en((in_valid && in_ready) || result_wr_en), .wr_addr(input_wr_addr),
        .wr_bytes(input_wr_bytes), .wr_data(input_wr_data),
        .rd0_addr(input_rd0_addr), .rd0_data(input_rd0),
        .rd1_addr(int_pos), .rd1_data(input_rd1)
    );

    function automatic [7:0] word_byte(input [31:0] word,input [1:0] index);
        begin
            case (index)
                2'd0: word_byte = word[31:24];
                2'd1: word_byte = word[23:16];
                2'd2: word_byte = word[15:8];
                2'd3: word_byte = word[7:0];
                default: word_byte = 8'b0;
            endcase
        end
    endfunction

    // Two-bit offsets select within one 32-bit word; they are not lengths.
    wire [1:0] mac_offset = enc_pos[1:0]-b_len[1:0];
    reg [31:0] enc_in,int_in;
    integer k;
    always @* begin
        enc_in = 0;
        int_in = 0;
        cipher_data = 0;
        for (k=0;
             k<4;
             k=k+1) begin
            if (k<{16'b0,enc_left}) begin
                if (k<{16'b0,enc_b_left})
                    enc_in[31-8*k -: 8] = input_rd0[127-8*k -: 8];
                else if (mode_q==3'd2)
                    enc_in[31-8*k -: 8] = word_byte(mac_q,mac_offset+k[1:0]);
            end
            if (k<{16'b0,int_left})
                int_in[31-8*k -: 8] = input_rd1[31-8*k -: 8];
        end
        for (k=0;
             k<16;
             k=k+1) begin
            if (state==OUTPUT && k<{16'b0,out_n})
                cipher_data[127-8*k -: 8] = input_rd0[127-8*k -: 8];
        end
    end

    mdm_cipher #(.AES_LOW_AREA(AES_LOW_AREA)) u_cipher (
        .clk(clk), .rst_n(rst_n), .start(enc_start), .alg(enc_alg_q), .key(enc_key_q),
        .count(count_q), .bearer(bearer_q), .direction(direction_q), .length(enc_len),
        .in_valid(enc_in_valid), .in_ready(enc_in_ready), .in_data(enc_in),
        .out_valid(enc_out_valid), .out_ready(1'b1), .out_data(enc_out),
        .out_bytes(enc_out_bytes), .done(enc_done)
    );
    mdm_integrity #(.AES_LOW_AREA(AES_LOW_AREA)) u_integrity (
        .clk(clk), .rst_n(rst_n), .start(int_start), .alg(int_alg_q), .key(int_key_q),
        .count(count_q), .bearer(bearer_q), .direction(direction_q), .length(int_len),
        .in_valid(int_in_valid), .in_ready(int_in_ready), .in_data(int_in),
        .mac(calculated_mac), .done(int_done)
    );

    // FSM section 1: state register only.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // FSM section 2: next-state logic only.
    always @* begin
        next_state = state;
        case (state)
            IDLE: if (cmd_valid && cmd_ready) begin
                if (cmd_bad)
                    next_state = RESPONSE;
                else if (cmd_a_bytes!=0)
                    next_state = LOAD_A;
                else if (cmd_b_bytes!=0)
                    next_state = LOAD_B;
                else
                    next_state = RUN;
            end
            LOAD_A: if (in_valid && in_ready && load_left<=16'd16) begin
                if (b_len!=0)
                    next_state = LOAD_B;
                else
                    next_state = RUN;
            end
            LOAD_B: if (in_valid && in_ready && load_left<=16'd16) next_state = RUN;
            RUN: if (enc_finished && int_finished) next_state = RESPONSE;
            RESPONSE: if (rsp_valid && rsp_ready) begin
                if (cipher_len==0)
                    next_state = IDLE;
                else
                    next_state = OUTPUT;
            end
            OUTPUT: if (cipher_valid && cipher_ready && out_left<=16'd16) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // FSM section 3: interface output logic and separate datapath registers.
    assign cmd_ready = rst_n && (state==IDLE);
    assign in_ready = (state==LOAD_A || state==LOAD_B);
    assign rsp_valid = (state==RESPONSE);
    assign rsp_mac = mac_q;
    assign rsp_mac_valid = mac_valid_q;
    assign rsp_rx_mac = rx_mac_q;
    assign rsp_rx_mac_valid = rx_mac_valid_q;
    assign rsp_mac_match = rx_mac_valid_q && int_finished && (mac_q==rx_mac_q);
    assign rsp_cipher_bytes = cipher_len;
    assign rsp_error = error_q;
    assign cipher_valid = (state==OUTPUT);
    assign cipher_keep = (state==OUTPUT) ? (16'hffff << (16'd16-out_n)) : 16'b0;
    assign cipher_last = (state==OUTPUT) && (out_left<=16'd16);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mode_q <= 0;
            enc_alg_q <= 0;
            int_alg_q <= 0;
            enc_key_q <= 0;
            int_key_q <= 0;
            count_q <= 0;
            bearer_q <= 0;
            direction_q <= 0;
            a_len <= 0;
            b_len <= 0;
            total_len <= 0;
            cipher_len <= 0;
            load_pos <= 0;
            enc_pos <= 0;
            int_pos <= 0;
            out_pos <= 0;
            mac_q <= 0;
            rx_mac_q <= 0;
            mac_valid_q <= 0;
            rx_mac_valid_q <= 0;
            error_q <= 0;
            enc_started <= 0;
            int_started <= 0;
            enc_finished <= 0;
            int_finished <= 0;
        end else begin
            case (state)
                IDLE: if (cmd_valid && cmd_ready) begin
                    mode_q <= cmd_mode;
                    enc_alg_q <= cmd_cipher_alg;
                    int_alg_q <= cmd_int_alg;
                    enc_key_q <= cmd_cipher_key;
                    int_key_q <= cmd_int_key;
                    count_q <= cmd_count;
                    bearer_q <= cmd_bearer;
                    direction_q <= cmd_direction;
                    a_len <= cmd_a_bytes;
                    b_len <= cmd_b_bytes;
                    total_len <= cmd_total;
                    load_pos <= 0;
                    enc_pos <= 0;
                    int_pos <= 0;
                    out_pos <= 0;
                    mac_q <= 0;
                    rx_mac_q <= 0;
                    rx_mac_valid_q <= 0;
                    enc_started <= 0;
                    int_started <= 0;
                    enc_finished <= (cmd_mode==3'd1);
                    int_finished <= (cmd_mode==3'd0);
                    if (cmd_bad) begin
                        error_q <= 1;
                        mac_valid_q <= 0;
                        cipher_len <= 0;
                    end else begin
                        error_q <= 0;
                        mac_valid_q <= (cmd_mode!=3'd0);
                        if (cmd_mode==3'd5)
                            cipher_len <= cmd_b_bytes-16'd4;
                        else
                            cipher_len <= cmd_b_bytes + ((cmd_mode==3'd2) ? 16'd4 : 16'd0);
                    end
                end
                LOAD_A,LOAD_B: if (in_valid && in_ready)
                    load_pos <= load_pos+load_n;
                RUN: begin
                    if (enc_start)
                        enc_started <= 1;
                    if (int_start)
                        int_started <= 1;
                    if (result_wr_en) begin
                        enc_pos <= enc_pos+enc_out_bytes;
                        // A rolling four-byte window extracts a possibly
                        // unaligned MAC without stealing the integrity read.
                        if (mode_q==3'd5) begin
                            case (enc_out_bytes)
                                16'd1: rx_mac_q <= {rx_mac_q[23:0],enc_out[31:24]};
                                16'd2: rx_mac_q <= {rx_mac_q[15:0],enc_out[31:16]};
                                16'd3: rx_mac_q <= {rx_mac_q[7:0],enc_out[31:8]};
                                16'd4: rx_mac_q <= enc_out;
                                default: rx_mac_q <= rx_mac_q;
                            endcase
                        end
                    end
                    if (int_in_valid && int_in_ready) begin
                        if (int_len-int_pos<=16'd4)
                            int_pos <= int_len;
                        else
                            int_pos <= int_pos+16'd4;
                    end
                    if (enc_done)
                        enc_finished <= 1;
                    if (capture_rx_mac)
                        rx_mac_valid_q <= 1;
                    if (int_done) begin
                        int_finished <= 1;
                        mac_q <= calculated_mac;
                    end
                end
                RESPONSE: if (rsp_valid && rsp_ready && cipher_len!=0)
                    out_pos <= 0;
                OUTPUT: if (cipher_valid && cipher_ready && out_left>16'd16)
                    out_pos <= out_pos+16'd16;
                default: ;
            endcase
        end
    end
endmodule
