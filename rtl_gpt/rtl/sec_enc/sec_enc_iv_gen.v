module sec_enc_iv_gen (
    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    output wire [127:0] o_iv
);

    wire [31:0] iv_even;

    assign iv_even = {
        i_bearer,
        i_direction,
        26'b0
    };

    assign o_iv = {
        iv_even,
        i_count,
        iv_even,
        i_count
    };

endmodule