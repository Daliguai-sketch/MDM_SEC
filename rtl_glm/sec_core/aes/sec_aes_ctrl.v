//============================================================================
// Module : sec_aes_ctrl
// Desc   : AES controller — CTR-mode cipher + CMAC integrity.
//          Converted from Python sec_aes_ctrl.py (fun_cipher / fun_gen_mac).
// Sec modes: 0:enc, 1:int, 2:int2enc, 3:enc2int
//============================================================================
module sec_aes_ctrl (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_start,
    input  wire [1:0]   i_sec_mode,
    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,
    input  wire [127:0] i_int_key,
    input  wire [127:0] i_enc_key,
    input  wire [31:0]  i_enc_data,
    input  wire         i_enc_data_vld,
    input  wire         i_enc_last,
    input  wire [1:0]   i_enc_byte_cnt,
    input  wire [31:0]  i_int_data,
    input  wire         i_int_data_vld,
    input  wire         i_int_last,
    output reg  [31:0]  o_cipher_data,
    output reg          o_cipher_vld,
    output reg          o_cipher_last,
    output reg  [31:0]  o_mac_data,
    output reg          o_mac_vld,
    output reg          o_mac_last,
    output reg          o_done
);

    // IV generation (from Python run_aes)
    wire [127:0] enc_iv = {i_count,
                           (i_bearer << 27) | (i_direction << 26),
                           32'h0, 32'h0};
    wire [127:0] int_iv_init = {i_count,
                                (i_bearer << 27) | (i_direction << 26),
                                32'h0, 32'h0};

    // AES core instance (shared for cipher + MAC)
    reg         aes_start;
    reg  [127:0] aes_key;
    reg  [127:0] aes_msg;
    wire         aes_done;
    wire [127:0] aes_stream;

    sec_aes_enc_core u_aes_core (
        .i_clk   (i_clk),
        .i_rst_n (i_rst_n),
        .i_start (aes_start),
        .i_key   (aes_key),
        .i_msg   (aes_msg),
        .o_done  (aes_done),
        .o_stream(aes_stream)
    );

    // CMAC subkeys: K1/K2 from L = AES(key, 0)
    wire        L_msb   = aes_stream[127];
    wire [127:0] L_sh   = {aes_stream[126:0], 1'b0};
    wire [127:0] K1_c   = L_msb ? (L_sh ^ 128'h87) : L_sh;
    wire        K1_msb  = K1_c[127];
    wire [127:0] K1_sh  = {K1_c[126:0], 1'b0};
    wire [127:0] K2_c   = K1_msb ? (K1_sh ^ 128'h87) : K1_sh;

    // FSM states
    localparam S_IDLE=5'd0, S_CALC_L=5'd1, S_CALC_K=5'd2;
    localparam S_CTR_LOAD=5'd4, S_CTR_ENC=5'd5, S_CTR_XOR=5'd6;
    localparam S_MAC_LOAD=5'd7, S_MAC_PROC=5'd8, S_MAC_LAST=5'd9;
    localparam S_DONE=5'd10;

    reg [4:0]   state;
    reg [127:0] ctr_iv;
    reg [2:0]   word_cnt;
    reg [127:0] block_buf;
    reg [127:0] mac_chain;
    reg [12:0]  blk_idx;
    reg         enc_active, int_active;
    reg         subkey_done;
    reg [127:0] K1, K2;

    // FSM
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state <= S_IDLE; aes_start <= 1'b0; aes_key <= 128'h0; aes_msg <= 128'h0;
            o_done <= 1'b0; o_cipher_data <= 32'h0; o_cipher_vld <= 1'b0; o_cipher_last <= 1'b0;
            o_mac_data <= 32'h0; o_mac_vld <= 1'b0; o_mac_last <= 1'b0;
            word_cnt <= 3'd0; block_buf <= 128'h0; ctr_iv <= 128'h0; mac_chain <= 128'h0;
            blk_idx <= 13'd0; K1 <= 128'h0; K2 <= 128'h0; subkey_done <= 1'b0;
            enc_active <= 1'b0; int_active <= 1'b0;
        end else begin
            aes_start <= 1'b0; o_cipher_vld <= 1'b0; o_mac_vld <= 1'b0; o_done <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (i_start) begin
                        enc_active <= (i_sec_mode != 2'd1);
                        int_active <= (i_sec_mode != 2'd0);
                        if (int_active) begin
                            aes_key <= i_int_key; aes_msg <= 128'h0;
                            aes_start <= 1'b1; state <= S_CALC_L; subkey_done <= 1'b0;
                        end else begin
                            ctr_iv <= enc_iv; blk_idx <= 13'd0; state <= S_CTR_LOAD;
                        end
                    end
                end
                S_CALC_L: if (aes_done) state <= S_CALC_K;
                S_CALC_K: begin
                    K1 <= K1_c; K2 <= K2_c; subkey_done <= 1'b1; mac_chain <= int_iv_init;
                    if (enc_active) begin
                        ctr_iv <= enc_iv; blk_idx <= 13'd0; state <= S_CTR_LOAD;
                    end else state <= S_MAC_LOAD;
                end
                S_CTR_LOAD: begin
                    if (i_enc_data_vld) begin
                        case (word_cnt)
                            3'd0: block_buf[127:96] <= i_enc_data;
                            3'd1: block_buf[95:64]  <= i_enc_data;
                            3'd2: block_buf[63:32]  <= i_enc_data;
                            3'd3: block_buf[31:0]   <= i_enc_data;
                        endcase
                        if (word_cnt == 3'd3) begin
                            word_cnt <= 3'd0; aes_key <= i_enc_key; aes_msg <= ctr_iv;
                            aes_start <= 1'b1; state <= S_CTR_ENC;
                        end else word_cnt <= word_cnt + 3'd1;
                    end
                end
                S_CTR_ENC: if (aes_done) state <= S_CTR_XOR;
                S_CTR_XOR: begin
                    case (word_cnt)
                        3'd0: begin
                            o_cipher_data <= aes_stream[127:96] ^ block_buf[127:96];
                            o_cipher_vld <= 1'b1; word_cnt <= 3'd1;
                        end
                        3'd1: begin
                            o_cipher_data <= aes_stream[95:64] ^ block_buf[95:64];
                            o_cipher_vld <= 1'b1; word_cnt <= 3'd2;
                        end
                        3'd2: begin
                            o_cipher_data <= aes_stream[63:32] ^ block_buf[63:32];
                            o_cipher_vld <= 1'b1; word_cnt <= 3'd3;
                        end
                        3'd3: begin
                            o_cipher_data <= aes_stream[31:0] ^ block_buf[31:0];
                            o_cipher_vld <= 1'b1; o_cipher_last <= i_enc_last;
                            word_cnt <= 3'd0; ctr_iv[12:0] <= (blk_idx+13'd1) & 13'h1FFF;
                            blk_idx <= blk_idx + 13'd1;
                            if (i_enc_last) begin
                                if (int_active && !subkey_done) state <= S_CALC_L;
                                else if (int_active) state <= S_MAC_LOAD;
                                else state <= S_DONE;
                            end else state <= S_CTR_LOAD;
                        end
                    endcase
                end
                S_MAC_LOAD: begin
                    if (i_int_data_vld) begin
                        case (word_cnt)
                            3'd0: block_buf[127:96] <= i_int_data;
                            3'd1: block_buf[95:64]  <= i_int_data;
                            3'd2: block_buf[63:32]  <= i_int_data;
                            3'd3: block_buf[31:0]   <= i_int_data;
                        endcase
                        if (word_cnt == 3'd3) begin
                            word_cnt <= 3'd0; aes_key <= i_int_key;
                            aes_msg <= mac_chain ^ block_buf; aes_start <= 1'b1;
                            state <= S_MAC_PROC;
                        end else word_cnt <= word_cnt + 3'd1;
                    end
                end
                S_MAC_PROC: begin
                    if (aes_done) begin
                        mac_chain <= aes_stream;
                        if (i_int_last) begin
                            aes_key <= i_int_key; aes_msg <= aes_stream ^ K1;
                            aes_start <= 1'b1; state <= S_MAC_LAST;
                        end else state <= S_MAC_LOAD;
                    end
                end
                S_MAC_LAST: begin
                    if (aes_done) begin
                        o_mac_data <= aes_stream[127:96]; o_mac_vld <= 1'b1;
                        o_mac_last <= 1'b1; state <= S_DONE;
                    end
                end
                S_DONE: begin o_done <= 1'b1; state <= S_IDLE; end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
