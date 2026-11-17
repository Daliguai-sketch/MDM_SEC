// Selectable AES-128 implementation. The default shares four S-boxes and
// uses 50 clocks/block; AES_LOW_AREA=0 retains the previous 5-clock core.
// Both variants implement the same start/ready/done interface.
module mdm_aes128 #(
    parameter integer AES_LOW_AREA=1
) (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    output wire         ready,
    input  wire [127:0] key,
    input  wire [127:0] block_in,
    output wire         busy,
    output wire         done,
    output wire [127:0] block_out
);
    generate
        if (AES_LOW_AREA!=0 && AES_LOW_AREA!=1) begin: g_invalid_aes_low_area
            initial begin
                $display("ERROR: AES_LOW_AREA must be 0 or 1");
                $finish;
            end
        end
        if (AES_LOW_AREA==1) begin: g_low_area
            mdm_aes128_serial u_core (
                .clk(clk), .rst_n(rst_n), .start(start), .ready(ready),
                .key(key), .block_in(block_in), .busy(busy), .done(done), .block_out(block_out)
            );
        end else begin: g_fast
            mdm_aes128_fast u_core (
                .clk(clk), .rst_n(rst_n), .start(start), .ready(ready),
                .key(key), .block_in(block_in), .busy(busy), .done(done), .block_out(block_out)
            );
        end
    endgenerate
endmodule
