// Sixteen byte banks permit an unaligned 1..16-byte write and 128-bit read
// each clock. A second independent 32-bit read port is used by integrity.
// Each bank has one write port. Reads are asynchronous in this generic RTL.
// Replace/pipeline this module for target memories with synchronous reads.
module mdm_packet_buffer #(
    parameter integer CAP_BYTES=2048,
    parameter integer READ_PORTS=2
) (
    input  wire         clk,
    input  wire         wr_en,
    input  wire [15:0]  wr_addr,
    input  wire [15:0]  wr_bytes,
    input  wire [127:0] wr_data,
    input  wire [15:0]  rd0_addr,
    output wire [127:0] rd0_data,
    input  wire [15:0]  rd1_addr,
    output wire [31:0]  rd1_data
);
    localparam integer DEPTH = (CAP_BYTES+15)/16;
    localparam integer AW = (DEPTH<=1) ? 1 : $clog2(DEPTH);

    // Shared four-stage byte barrel rotators avoid sixteen independent
    // 16-to-1 crossbars on each 128-bit memory port.
    function automatic [127:0] rotate_left(input [127:0] x,input [3:0] n);
        reg [127:0] t;
        begin
            t = n[3] ? {x[63:0],x[127:64]} : x;
            t = n[2] ? {t[95:0],t[127:96]} : t;
            t = n[1] ? {t[111:0],t[127:112]} : t;
            t = n[0] ? {t[119:0],t[127:120]} : t;
            rotate_left = t;
        end
    endfunction
    function automatic [127:0] rotate_right(input [127:0] x,input [3:0] n);
        reg [127:0] t;
        begin
            t = n[3] ? {x[63:0],x[127:64]} : x;
            t = n[2] ? {t[31:0],t[127:32]} : t;
            t = n[1] ? {t[15:0],t[127:16]} : t;
            t = n[0] ? {t[7:0],t[127:8]} : t;
            rotate_right = t;
        end
    endfunction

    wire [127:0] write_banks = rotate_right(wr_data,wr_addr[3:0]);
    wire [127:0] read_banks0,read_banks1;
    wire [127:0] read1_aligned = rotate_left(read_banks1,rd1_addr[3:0]);
    assign rd0_data = rotate_left(read_banks0,rd0_addr[3:0]);
    assign rd1_data = read1_aligned[127:96];
    genvar b;
    generate
        for (b=0;
             b<16;
             b=b+1) begin: g_bank
            localparam [3:0] BANK = b[3:0];
            reg [7:0] mem [0:DEPTH-1];
            wire [3:0] wo = BANK-wr_addr[3:0];
            wire [3:0] ro0 = BANK-rd0_addr[3:0];
            wire [3:0] ro1 = BANK-rd1_addr[3:0];
            wire [15:0] wbyte = wr_addr+{12'b0,wo};
            wire [15:0] rbyte0 = rd0_addr+{12'b0,ro0};
            wire [15:0] rbyte1 = rd1_addr+{12'b0,ro1};
            always @(posedge clk) begin
                if (wr_en && {12'b0,wo}<wr_bytes)
                    mem[wbyte[AW+3:4]] <= write_banks[127-8*b -: 8];
            end
            assign read_banks0[127-8*b -: 8] = mem[rbyte0[AW+3:4]];
            if (READ_PORTS==2) begin: g_second_read
                assign read_banks1[127-8*b -: 8] = mem[rbyte1[AW+3:4]];
            end else begin: g_no_second_read
                assign read_banks1[127-8*b -: 8] = 8'b0;
            end
        end
    endgenerate
endmodule
