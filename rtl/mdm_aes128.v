// Selectable AES-128 implementation. AES_LOW_AREA is a historical parameter
// name: 1 selects the default 50-cycle serial core, 0 the original 5-cycle
// core, and 2 a 5-cycle balanced core. BALANCED_TIMING_OPT selects the
// timing-oriented version only for mode 2; the default retains the original.
module mdm_aes128 #(
    parameter integer AES_LOW_AREA=1,
    parameter integer BALANCED_TIMING_OPT=0
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
        if (AES_LOW_AREA!=0 && AES_LOW_AREA!=1 && AES_LOW_AREA!=2) begin: g_invalid_aes_low_area
            initial begin
                $display("ERROR: AES_LOW_AREA must be 0, 1 or 2");
                $finish;
            end
        end
        if (BALANCED_TIMING_OPT!=0 && BALANCED_TIMING_OPT!=1) begin: g_invalid_balanced_timing_opt
            initial begin
                $display("ERROR: BALANCED_TIMING_OPT must be 0 or 1");
                $finish;
            end
        end
        if (AES_LOW_AREA==1) begin: g_low_area
            mdm_aes128_serial u_core (
                .clk(clk), .rst_n(rst_n), .start(start), .ready(ready),
                .key(key), .block_in(block_in), .busy(busy), .done(done), .block_out(block_out)
            );
        end else if (AES_LOW_AREA==2 && BALANCED_TIMING_OPT==1) begin: g_balanced_timing
            mdm_aes128_balanced_timing u_core (
                .clk(clk), .rst_n(rst_n), .start(start), .ready(ready),
                .key(key), .block_in(block_in), .busy(busy), .done(done), .block_out(block_out)
            );
        end else if (AES_LOW_AREA==2) begin: g_balanced
            mdm_aes128_balanced u_core (
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
