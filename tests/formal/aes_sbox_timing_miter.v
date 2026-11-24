// Prove the flat timing-oriented S-box matches the original hierarchical
// circuit for every possible 8-bit input. The primitive regression also
// compares both implementations with an independent 256-entry AES table.
module aes_sbox_timing_miter (
    input wire [7:0] value,
    output wire mismatch
);
    wire [7:0] original, timing;
    mdm_aes_sbox u_original (.value(value), .result(original));
    mdm_aes_sbox_timing u_timing (.value(value), .result(timing));
    assign mismatch = original != timing;
endmodule
