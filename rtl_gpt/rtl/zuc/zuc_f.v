module zuc_f (
    input  wire [31:0] x0,
    input  wire [31:0] x1,
    input  wire [31:0] x2,

    input  wire [31:0] r1,
    input  wire [31:0] r2,

    output wire [31:0] w,
    output wire [31:0] r1_next,
    output wire [31:0] r2_next
);

    wire [31:0] w1;
    wire [31:0] w2;

    wire [31:0] l1_in;
    wire [31:0] l2_in;

    wire [31:0] u;
    wire [31:0] v;


    /*
     * Rotate left
     */

    function [31:0] rotl32;

        input [31:0] value;
        input integer shift;

        begin

            rotl32 =
                (value << shift) |
                (value >> (32 - shift));

        end

    endfunction


    /*
     * Linear transformation L1
     */

    function [31:0] L1;

        input [31:0] value;

        begin

            L1 =
                value ^
                rotl32(value, 2) ^
                rotl32(value, 10) ^
                rotl32(value, 18) ^
                rotl32(value, 24);

        end

    endfunction


    /*
     * Linear transformation L2
     */

    function [31:0] L2;

        input [31:0] value;

        begin

            L2 =
                value ^
                rotl32(value, 8) ^
                rotl32(value, 14) ^
                rotl32(value, 22) ^
                rotl32(value, 30);

        end

    endfunction


    assign w =
        (x0 ^ r1) + r2;

    assign w1 =
        r1 + x1;

    assign w2 =
        r2 ^ x2;


    assign l1_in = {
        w1[15:0],
        w2[31:16]
    };

    assign l2_in = {
        w2[15:0],
        w1[31:16]
    };


    assign u = L1(l1_in);
    assign v = L2(l2_in);


    /*
     * R1_next = SBOX(U)
     *
     * SBOX pattern:
     *
     * {S0[b0], S1[b1], S0[b2], S1[b3]}
     */

    zuc_sbox_s0 u_s0_0 (
        .i_data (u[31:24]),
        .o_data (r1_next[31:24])
    );

    zuc_sbox_s1 u_s1_0 (
        .i_data (u[23:16]),
        .o_data (r1_next[23:16])
    );

    zuc_sbox_s0 u_s0_1 (
        .i_data (u[15:8]),
        .o_data (r1_next[15:8])
    );

    zuc_sbox_s1 u_s1_1 (
        .i_data (u[7:0]),
        .o_data (r1_next[7:0])
    );


    /*
     * R2_next = SBOX(V)
     */

    zuc_sbox_s0 u_s0_2 (
        .i_data (v[31:24]),
        .o_data (r2_next[31:24])
    );

    zuc_sbox_s1 u_s1_2 (
        .i_data (v[23:16]),
        .o_data (r2_next[23:16])
    );

    zuc_sbox_s0 u_s0_3 (
        .i_data (v[15:8]),
        .o_data (r2_next[15:8])
    );

    zuc_sbox_s1 u_s1_3 (
        .i_data (v[7:0]),
        .o_data (r2_next[7:0])
    );

endmodule