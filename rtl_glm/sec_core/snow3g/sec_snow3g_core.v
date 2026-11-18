//============================================================================
// Module : sec_snow3g_core
// Desc   : SNOW 3G stream cipher core (ETSI/SAGE v1.1, 3GPP UEA2/UIA2).
//          Converted from Python sec_snow3g_core.py.
//          Implements LFSR(16×32-bit) + FSM(3×32-bit) + S1/S2 + MULalpha/DIValpha.
//          One step per clock cycle. 32 init cycles (with feedback) then
//          keystream generation (without feedback).
//============================================================================
module sec_snow3g_core (
    input  wire         i_clk,
    input  wire         i_rst_n,
    input  wire         i_start,       // pulse: load key/IV, begin init
    input  wire         i_step,        // 1: advance one clock (init or keystream)
    input  wire         i_init,        // 1: init mode (feedback on), 0: keystream
    input  wire [127:0] i_key,         // key[0]=i_key[127:96] ... key[3]=i_key[31:0]
    input  wire [127:0] i_iv,          // iv[0]=i_iv[127:96] ... iv[3]=i_iv[31:0]
    output wire [31:0]  o_zt,          // keystream word
    output wire         o_zt_vld       // keystream valid (after each step)
);

    //========================================================================
    // MULx function: GF(2^8) multiply by x
    //========================================================================
    function [7:0] mulx;
        input [7:0] v;
        input [7:0] c;
        begin
            mulx = v[7] ? ((v << 1) ^ c) : (v << 1);
        end
    endfunction

    //========================================================================
    // MULxPOW: apply MULx i times (constant loop, synthesizable)
    //========================================================================
    function [7:0] mulxpow_a9_23;
        input [7:0] v; reg [7:0] r; integer j;
        begin r=v; for(j=0;j<23;j=j+1) r=mulx(r,8'hA9); mulxpow_a9_23=r; end
    endfunction
    function [7:0] mulxpow_a9_245;
        input [7:0] v; reg [7:0] r; integer j;
        begin r=v; for(j=0;j<245;j=j+1) r=mulx(r,8'hA9); mulxpow_a9_245=r; end
    endfunction
    function [7:0] mulxpow_a9_48;
        input [7:0] v; reg [7:0] r; integer j;
        begin r=v; for(j=0;j<48;j=j+1) r=mulx(r,8'hA9); mulxpow_a9_48=r; end
    endfunction
    function [7:0] mulxpow_a9_239;
        input [7:0] v; reg [7:0] r; integer j;
        begin r=v; for(j=0;j<239;j=j+1) r=mulx(r,8'hA9); mulxpow_a9_239=r; end
    endfunction
    function [7:0] mulxpow_a9_16;
        input [7:0] v; reg [7:0] r; integer j;
        begin r=v; for(j=0;j<16;j=j+1) r=mulx(r,8'hA9); mulxpow_a9_16=r; end
    endfunction
    function [7:0] mulxpow_a9_39;
        input [7:0] v; reg [7:0] r; integer j;
        begin r=v; for(j=0;j<39;j=j+1) r=mulx(r,8'hA9); mulxpow_a9_39=r; end
    endfunction
    function [7:0] mulxpow_a9_6;
        input [7:0] v; reg [7:0] r; integer j;
        begin r=v; for(j=0;j<6;j=j+1) r=mulx(r,8'hA9); mulxpow_a9_6=r; end
    endfunction
    function [7:0] mulxpow_a9_64;
        input [7:0] v; reg [7:0] r; integer j;
        begin r=v; for(j=0;j<64;j=j+1) r=mulx(r,8'hA9); mulxpow_a9_64=r; end
    endfunction

    //========================================================================
    // MULalpha(byte) → 32-bit, DIValpha(byte) → 32-bit
    //========================================================================
    function [31:0] mulalpha;
        input [7:0] c;
        begin
            mulalpha = {mulxpow_a9_23(c), mulxpow_a9_245(c),
                        mulxpow_a9_48(c), mulxpow_a9_239(c)};
        end
    endfunction
    function [31:0] divalpha;
        input [7:0] c;
        begin
            divalpha = {mulxpow_a9_16(c), mulxpow_a9_39(c),
                        mulxpow_a9_6(c),  mulxpow_a9_64(c)};
        end
    endfunction

    //========================================================================
    // S1, S2: 32-bit → 32-bit using SR/SQ S-boxes + MULx matrix
    //========================================================================
    // S-box instance wires
    wire [7:0] sr_out [0:3];  // for S1
    wire [7:0] sq_out [0:3];  // for S2

    // S1 input bytes (from R0 register)
    wire [7:0] s1_b0, s1_b1, s1_b2, s1_b3;
    // S2 input bytes (from R1 register)
    wire [7:0] s2_b0, s2_b1, s2_b2, s2_b3;
