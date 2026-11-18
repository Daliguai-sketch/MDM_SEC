module aes_key_expand_step (
    input  wire [127:0] i_key,      // Format: {w0, w1, w2, w3}
    input  wire [31:0]  i_rcon,     // Format: 32'h01000000, etc.
    output wire [127:0] o_next_key  // Format: {nw0, nw1, nw2, nw3}
);

    wire [31:0] w0, w1, w2, w3;
    wire [31:0] rot_word;
    wire [7:0]  sb0, sb1, sb2, sb3;
    wire [31:0] sub_word;
    wire [31:0] temp;
    wire [31:0] nw0, nw1, nw2, nw3;

    // MDM_SEC Word Definition
    assign w0 = i_key[127:96];
    assign w1 = i_key[95:64];
    assign w2 = i_key[63:32];
    assign w3 = i_key[31:0];

    // RotWord on w3
    assign rot_word = {w3[23:0], w3[31:24]};

    // SubWord via aes_sbox (.din / .dout)
    aes_sbox u_sb0 (.din(rot_word[31:24]), .dout(sb0));
    aes_sbox u_sb1 (.din(rot_word[23:16]), .dout(sb1));
    aes_sbox u_sb2 (.din(rot_word[15:8]),  .dout(sb2));
    aes_sbox u_sb3 (.din(rot_word[7:0]),   .dout(sb3));

    assign sub_word = {sb0, sb1, sb2, sb3};
    assign temp     = sub_word ^ i_rcon;

    // XOR Chain
    assign nw0 = w0 ^ temp;
    assign nw1 = w1 ^ nw0;
    assign nw2 = w2 ^ nw1;
    assign nw3 = w3 ^ nw2;

    assign o_next_key = {nw0, nw1, nw2, nw3};

endmodule