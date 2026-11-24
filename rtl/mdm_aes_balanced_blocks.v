// Shared combinational stages for the balanced-opt five-cycle AES-128 core.
// These modules add no registers; two AES rounds remain combinational per clock.

module mdm_aes_balanced_add_round_key (
    input  wire [127:0] state_in,
    input  wire [127:0] round_key,
    output wire [127:0] state_out
);
    assign state_out = state_in ^ round_key;
endmodule

// First online key expansion: RotWord, four S-boxes and the standard AES-128
// word-XOR chain. Reuse the existing serial-core word-XOR module.
module mdm_aes_balanced_key_expand1 (
    input  wire [127:0] key_in,
    input  wire [7:0]   rcon,
    output wire [127:0] key_out
);
    wire [31:0] subword;
    mdm_aes_subbytes4 u_subword (
        .data_in({key_in[23:0],key_in[31:24]}), .data_out(subword)
    );
    mdm_aes_key_expand u_word_xor (
        .key_in(key_in), .subword(subword), .rcon(rcon), .key_out(key_out)
    );
endmodule

// The second expansion uses factored XOR equations. key_in is the key before
// the first expansion; key1 is its result.
module mdm_aes_balanced_key_expand2 (
    input  wire [127:0] key_in,
    input  wire [127:0] key1,
    input  wire [7:0]   rcon,
    output wire [127:0] key_out
);
    wire [31:0] subword, t2, a2, b2, c2, d2;
    mdm_aes_subbytes4 u_subword (
        .data_in({key1[23:0],key1[31:24]}), .data_out(subword)
    );
    assign t2 = subword ^ {rcon,24'b0};
    assign a2 = key1[127:96] ^ t2;
    assign b2 = key_in[95:64] ^ t2;
    assign c2 = key_in[63:32] ^ a2;
    assign d2 = key_in[31:0] ^ b2;
    assign key_out = {a2,b2,c2,d2};
endmodule
