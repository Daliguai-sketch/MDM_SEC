module aes_double_round (
    input  wire [127:0] state_in,

    input  wire [127:0] round_key_a,
    input  wire [127:0] round_key_b,

    input  wire         last_round_b,

    output wire [127:0] state_out
);

wire [127:0] middle_state;


// ============================================================
// Round A
// ============================================================

aes_round_comb u_round_a (

    .state_in   (state_in),

    .round_key  (round_key_a),

    .last_round (1'b0),

    .state_out  (middle_state)

);


// ============================================================
// Round B
// ============================================================

aes_round_comb u_round_b (

    .state_in   (middle_state),

    .round_key  (round_key_b),

    .last_round (last_round_b),

    .state_out  (state_out)

);

endmodule