// Hierarchical combinational datapath for the five-cycle AES-128 core.
// The stages follow the Python AES model's sub_bytes, shift_rows,
// mix_columns, add_round_key and key_expansion functions. No stage adds
// registers: mdm_aes128_balanced still performs two rounds per clock.

module mdm_aes_balanced_subbytes (
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);
    genvar i;
    generate
        for (i=0;
             i<16;
             i=i+1) begin: g_byte
            mdm_aes_sbox u_sbox (
                .value(state_in[127-8*i -: 8]),
                .result(state_out[127-8*i -: 8])
            );
        end
    endgenerate
endmodule

// A single 32-bit column uses the original 88-XOR balanced network. The
// function and its upstream license are kept in mdm_aes_mix_balanced.vh.
module mdm_aes_balanced_mix_column (
    input  wire [31:0] data_in,
    output wire [31:0] data_out
);
    `include "mdm_aes_mix_balanced.vh"
    assign data_out = aes_mix_column_balanced(data_in);
endmodule

module mdm_aes_balanced_mix_columns (
    input  wire [127:0] state_in,
    output wire [127:0] state_out
);
    genvar col;
    generate
        for (col=0;
             col<4;
             col=col+1) begin: g_column
            mdm_aes_balanced_mix_column u_mix_column (
                .data_in(state_in[127-32*col -: 32]),
                .data_out(state_out[127-32*col -: 32])
            );
        end
    endgenerate
endmodule

module mdm_aes_balanced_add_round_key (
    input  wire [127:0] state_in,
    input  wire [127:0] round_key,
    output wire [127:0] state_out
);
    assign state_out = state_in ^ round_key;
endmodule

// The first of the two rounds always mixes columns. The second may be the
// AES last round and needs a bypass. Specializing the first instance removes
// its unnecessary bypass mux even when hierarchy is preserved by synthesis.
module mdm_aes_balanced_round #(
    parameter integer MAY_SKIP_MIX=0
) (
    input  wire [127:0] state_in,
    input  wire [127:0] round_key,
    input  wire         last_round,
    output wire [127:0] state_out
);
    wire [127:0] substituted, shifted, mixed, selected;

    mdm_aes_balanced_subbytes u_subbytes (
        .state_in(state_in), .state_out(substituted)
    );
    mdm_aes_shift_rows u_shift_rows (
        .state_in(substituted), .state_out(shifted)
    );
    mdm_aes_balanced_mix_columns u_mix_columns (
        .state_in(shifted), .state_out(mixed)
    );
    generate
        if (MAY_SKIP_MIX != 0) begin: g_last_round_bypass
            assign selected = last_round ? shifted : mixed;
        end else begin: g_always_mix
            assign selected = mixed;
        end
    endgenerate
    mdm_aes_balanced_add_round_key u_add_round_key (
        .state_in(selected), .round_key(round_key), .state_out(state_out)
    );
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

// Second expansion preserves the balanced core's factored XOR equations.
// key_in is the key before the first expansion; key1 is its result.
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
