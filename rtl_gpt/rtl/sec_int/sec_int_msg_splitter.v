module sec_int_msg_splitter (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         i_clear,
    input  wire [1:0]   i_alg_sel,

    // 128-bit input
    input  wire [127:0] i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,

    input  wire         i_data_last,
    input  wire [4:0]   i_valid_bytes,

    // AES 128-bit output
    output wire [127:0] o_aes_data,
    output wire         o_aes_vld,
    input  wire         i_aes_ready,
    output wire         o_aes_last,
    output wire [4:0]   o_aes_valid_bytes,

    // SNOW3G 64-bit output
    output wire [63:0]  o_snow_data,
    output wire         o_snow_vld,
    input  wire         i_snow_ready,
    output wire [3:0]   o_snow_valid_bytes,

    // ZUC 32-bit output
    output wire [31:0]  o_zuc_data,
    output wire         o_zuc_vld,
    input  wire         i_zuc_ready,
    output wire [2:0]   o_zuc_valid_bytes
);

localparam ALG_AES  = 2'd0;
localparam ALG_SNOW = 2'd1;
localparam ALG_ZUC  = 2'd2;
localparam ALG_NULL = 2'd3;

reg [127:0] buffer_reg;
reg [4:0]   bytes_reg;
reg [2:0]   piece_index;  // for zuc 0/1/2/3-0/4/8/12Byte
reg         buffer_valid;

wire input_fire;
wire snow_fire;
wire zuc_fire;

wire [4:0] consumed_bytes;
wire [4:0] remaining_bytes;

wire [2:0] total_pieces;
assign consumed_bytes =
    (i_alg_sel == ALG_SNOW)
    ? (piece_index == 3'd0 ? 5'd0 : 5'd8)
    : ({2'b00, piece_index} << 2);

assign remaining_bytes =
    (bytes_reg > consumed_bytes)
    ? (bytes_reg - consumed_bytes)
    : 5'd0;

assign total_pieces =
    (i_alg_sel == ALG_SNOW)
    ? ((bytes_reg + 5'd7) >> 3)
    : ((bytes_reg + 5'd3) >> 2);

// AES direct path
assign o_aes_data = i_data;

assign o_aes_vld =
    !i_clear &&
    (i_alg_sel == ALG_AES) &&
    i_data_vld;

assign o_aes_last = i_data_last;
assign o_aes_valid_bytes = i_valid_bytes;

// SNOW3G output
assign o_snow_data =
    (piece_index == 3'd0)
    ? buffer_reg[127:64]
    : buffer_reg[63:0];

assign o_snow_vld =
    !i_clear &&
    (i_alg_sel == ALG_SNOW) &&
    buffer_valid;

assign o_snow_valid_bytes =
    (remaining_bytes >= 5'd8)
    ? 4'd8
    : {1'b0, remaining_bytes[2:0]};

// ZUC output
assign o_zuc_data =
    (piece_index == 3'd0) ? buffer_reg[127:96] :
    (piece_index == 3'd1) ? buffer_reg[95:64]  :
    (piece_index == 3'd2) ? buffer_reg[63:32]  :
                            buffer_reg[31:0];

assign o_zuc_vld =
    !i_clear &&
    (i_alg_sel == ALG_ZUC) &&
    buffer_valid;

assign o_zuc_valid_bytes =
    (remaining_bytes >= 5'd4)
    ? 3'd4
    : {1'b0, remaining_bytes[1:0]};

// Input ready
assign o_data_ready =
    !i_clear &&
    (
        ((i_alg_sel == ALG_AES) && i_aes_ready) ||
        ((i_alg_sel == ALG_SNOW) && !buffer_valid) ||
        ((i_alg_sel == ALG_ZUC) && !buffer_valid) ||
        (i_alg_sel == ALG_NULL)
    );

assign input_fire =
    i_data_vld && o_data_ready;

assign snow_fire =
    o_snow_vld && i_snow_ready;

assign zuc_fire =
    o_zuc_vld && i_zuc_ready;

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin
        buffer_reg <= 128'b0;
        bytes_reg <= 5'd0;
        piece_index <= 3'd0;
        buffer_valid <= 1'b0;
    end
    else if (i_clear) begin
        buffer_reg <= 128'b0;
        bytes_reg <= 5'd0;
        piece_index <= 3'd0;
        buffer_valid <= 1'b0;
    end
    else begin

        if (input_fire &&
            (i_alg_sel == ALG_SNOW ||
             i_alg_sel == ALG_ZUC)) begin

            buffer_reg <= i_data;
            bytes_reg <= i_valid_bytes;
            piece_index <= 3'd0;
            buffer_valid <= 1'b1;

        end

        if (snow_fire || zuc_fire) begin

            if (piece_index + 3'd1 >= total_pieces) begin

                buffer_valid <= 1'b0;
                piece_index <= 3'd0;

            end
            else begin

                piece_index <= piece_index + 3'd1;

            end

        end

    end

end

endmodule