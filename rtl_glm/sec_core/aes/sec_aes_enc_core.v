//============================================================================
// Module : sec_aes_enc_core
// Desc   : AES-128 encryption block cipher core (iterative, 11 cycles).
//          Converted from Python aes_enc_core() in sec_aes_core_enc.py.
//
// Algorithm (matching Python reference):
//   1. Load plaintext into state (column-major)
//   2. Round 0 : AddRoundKey(rk0)           — initial key addition
//   3. Round 1-9: SubBytes + ShiftRows + MixColumns + AddRoundKey
//   4. Round 10 : SubBytes + ShiftRows + AddRoundKey (no MixColumns)
//
// Interface (AXI-Stream-like, 128-bit):
//   i_clk, i_rst_n
//   i_start      : pulse to begin encryption
//   i_key[127:0] : AES-128 key
//   i_msg[127:0] : 128-bit plaintext block
//   o_done       : pulse when ciphertext is valid
//   o_stream[127:0]: 128-bit ciphertext
//============================================================================
module sec_aes_enc_core (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_start,
    input  wire [127:0] i_key,
    input  wire [127:0] i_msg,
    output reg          o_done,
    output reg  [127:0] o_stream
);

    // ---- States ----
    localparam IDLE   = 2'd0;
    localparam ROUND  = 2'd1;
    localparam FINISH = 2'd2;

    reg [1:0]  state;
    reg [3:0]  round_cnt;   // 0..10

    // ---- Key expansion (combinational) ----
    wire [127:0] rk0,  rk1,  rk2,  rk3,  rk4,  rk5,  rk6,  rk7;
    wire [127:0] rk8,  rk9,  rk10;

    sec_aes_key_expansion u_keyexp (
        .i_key (i_key),
        .o_rk0 (rk0),  .o_rk1 (rk1),  .o_rk2 (rk2),  .o_rk3 (rk3),
        .o_rk4 (rk4),  .o_rk5 (rk5),  .o_rk6 (rk6),  .o_rk7 (rk7),
        .o_rk8 (rk8),  .o_rk9 (rk9),  .o_rk10(rk10)
    );

    // ---- Round key mux ----
    reg  [127:0] round_key;
    wire [127:0] round_out;
    wire         is_last;

    // State register
    reg  [127:0] state_reg;

    // Round function instance (combinational)
    sec_aes_round u_round (
        .i_state (state_reg),
        .i_rk    (round_key),
        .i_last  (is_last),
        .o_state (round_out)
    );

    // ---- Round key selection ----
    always @(*) begin
        case (round_cnt)
            4'd0:  round_key = rk0;
            4'd1:  round_key = rk1;
            4'd2:  round_key = rk2;
            4'd3:  round_key = rk3;
            4'd4:  round_key = rk4;
            4'd5:  round_key = rk5;
            4'd6:  round_key = rk6;
            4'd7:  round_key = rk7;
            4'd8:  round_key = rk8;
            4'd9:  round_key = rk9;
            4'd10: round_key = rk10;
            default: round_key = 128'h0;
        endcase
    end

    // is_last: round 10 is the last (no MixColumns)
    // round 0: initial AddRoundKey only (bypass SubBytes/ShiftRows/MixColumns)
    assign is_last = (round_cnt == 4'd10);

    // ---- FSM ----
    always @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            state     <= IDLE;
            round_cnt <= 4'd0;
            state_reg <= 128'h0;
            o_stream  <= 128'h0;
            o_done    <= 1'b0;
        end else begin
            case (state)
                IDLE: begin
                    o_done <= 1'b0;
                    if (i_start) begin
                        // Round 0: initial AddRoundKey
                        state_reg <= i_msg ^ rk0;
                        round_cnt <= 4'd1;
                        state     <= ROUND;
                    end
                end

                ROUND: begin
                    state_reg <= round_out;  // register round result
                    if (round_cnt == 4'd10) begin
                        state <= FINISH;
                    end else begin
                        round_cnt <= round_cnt + 4'd1;
                    end
                end

                FINISH: begin
                    o_stream <= state_reg;
                    o_done   <= 1'b1;
                    state    <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
