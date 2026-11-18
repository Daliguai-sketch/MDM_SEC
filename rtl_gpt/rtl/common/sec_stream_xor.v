module sec_stream_xor (
    input  wire [127:0] i_data,
    input  wire [127:0] i_stream,

    output wire [127:0] o_data
);

assign o_data = i_data ^ i_stream;

endmodule