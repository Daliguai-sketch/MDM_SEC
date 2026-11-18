module aes_cmac_packer (

    input  wire         clk,
    input  wire         rst_n,

    // =====================================================
    // Message Start
    // =====================================================

    input  wire         i_start,
    output wire         o_start_ready,

    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    // =====================================================
    // 128-bit Message Input
    // =====================================================

    input  wire [127:0] i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,

    input  wire         i_data_last,
    input  wire [4:0]   i_valid_bytes,

    // =====================================================
    // 128-bit CMAC Block Output
    // =====================================================

    output wire [127:0] o_block,
    output wire         o_block_vld,
    input  wire         i_block_ready,

    output wire         o_block_last,
    output wire         o_block_complete,

    // =====================================================
    // Status
    // =====================================================

    output wire         o_busy

);


// =========================================================
// Internal Registers
// =========================================================

reg [255:0] buffer_reg;

reg [5:0] byte_count;

reg active_reg;

reg last_seen_reg;


// =========================================================
// Handshake
// =========================================================

wire start_accept;
wire input_accept;
wire output_accept;


// A new message can start only when the previous
// message has completely left the packer.

assign o_start_ready = !active_reg;

assign start_accept =
    i_start && o_start_ready;


// =========================================================
// Output Valid
// =========================================================

// When more than 16 bytes are available,
// the first block is definitely not the last block.
//
// When the final input has been received,
// the remaining 1~16 bytes form the final block.
//
// An exactly 16-byte block must be retained until
// its final/non-final status becomes known.

assign o_block_vld =
    active_reg &&
    (
        (byte_count > 6'd16) ||
        last_seen_reg
    );


// =========================================================
// Last Block
// =========================================================

assign o_block_last =
    o_block_vld &&
    last_seen_reg &&
    (byte_count <= 6'd16);


// =========================================================
// Complete Block
// =========================================================

// For CMAC:
//
// Complete final block -> K1
// Incomplete final block -> K2

assign o_block_complete =
    o_block_last &&
    (byte_count == 6'd16);


// =========================================================
// Output Handshake
// =========================================================

assign output_accept =
    o_block_vld &&
    i_block_ready;


// =========================================================
// Input Ready
// =========================================================

// A new 128-bit input may be appended when:
//
// 1. Message is active.
// 2. Final input has not been received.
// 3. Buffer has enough space.
//
// If an output block is consumed in the same cycle,
// that space is immediately available.

wire [5:0] remaining_bytes;

assign remaining_bytes =
    byte_count -
    (output_accept ? 6'd16 : 6'd0);

assign o_data_ready =
    active_reg &&
    !last_seen_reg &&
    (remaining_bytes <= 6'd16) &&
    (i_valid_bytes <= 5'd16);


// =========================================================
// Input Handshake
// =========================================================

assign input_accept =
    i_data_vld &&
    o_data_ready;


// =========================================================
// Padding Function
// =========================================================

// Valid bytes are located at MSB side.
//
// Example:
//
// valid_bytes = 5
//
// input:
// 11223344550000000000000000000000
//
// output:
// 11223344558000000000000000000000

function [127:0] pad_block;

    input [127:0] data;
    input [4:0] valid_bytes;

    reg [127:0] mask;
    reg [127:0] pad_bit;

    begin

        if (valid_bytes == 5'd16) begin

            pad_block = data;

        end
        else begin

            mask =
                128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
                << ((16-valid_bytes)*8);

            pad_bit =
                128'h80
                << ((15-valid_bytes)*8);

            pad_block =
                (data & mask) | pad_bit;

        end

    end

endfunction


// =========================================================
// Output Block
// =========================================================

assign o_block =
    (o_block_last && !o_block_complete)
    ?
    pad_block(
        buffer_reg[255:128],
        byte_count[4:0]
    )
    :
    buffer_reg[255:128];


// =========================================================
// Input Byte Mask
// =========================================================

wire [127:0] input_mask;

assign input_mask =
    (i_valid_bytes == 5'd16)
    ?
    128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
    :
    (
        128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF
        << ((16-i_valid_bytes)*8)
    );

wire [127:0] masked_input;

assign masked_input =
    i_data & input_mask;


// =========================================================
// Buffer Next-State Logic
// =========================================================

// This implementation supports:
//
// - Input only
// - Output only
// - Input and output in the same cycle
//
// The current output block is consumed first,
// then new valid input bytes are appended.

reg [255:0] buffer_next;

reg [5:0] byte_count_next;

reg active_next;
reg last_seen_next;

reg [255:0] temp_buffer;

reg [5:0] temp_count;

integer j;


// =========================================================
// Combinational Next State
// =========================================================

always @(*) begin

    buffer_next = buffer_reg;

    byte_count_next = byte_count;

    active_next = active_reg;

    last_seen_next = last_seen_reg;

    temp_buffer = buffer_reg;

    temp_count = byte_count;


    // -----------------------------------------------------
    // Start new message
    // -----------------------------------------------------

    if (start_accept) begin

        temp_buffer = {

            i_count,

            i_bearer,
            i_direction,
            26'b0,

            192'b0

        };

        temp_count = 6'd8;

        active_next = 1'b1;

        last_seen_next = 1'b0;

    end

    else begin

        // -------------------------------------------------
        // Consume output block
        // -------------------------------------------------

        if (output_accept) begin

            if (o_block_last) begin

                temp_buffer = 256'd0;

                temp_count = 6'd0;

                active_next = 1'b0;

                last_seen_next = 1'b0;

            end
            else begin

                temp_buffer = {
                    temp_buffer[127:0],
                    128'b0
                };

                temp_count = temp_count - 6'd16;

            end

        end


        // -------------------------------------------------
        // Append input data
        // -------------------------------------------------

        if (input_accept) begin

            // Append each valid byte to the first
            // available position in the buffer.
            //
            // This avoids incorrect variable shifts
            // when input and output occur together.

            for (j = 0; j < 16; j = j + 1) begin

                if (j < i_valid_bytes) begin

                    temp_buffer[
                        255 - 8*(temp_count+j) -: 8
                    ] = masked_input[127-8*j -: 8];

                end

            end

            temp_count =
                temp_count + {1'b0,i_valid_bytes};

            if (i_data_last)
                last_seen_next = 1'b1;

        end

    end


    buffer_next = temp_buffer;

    byte_count_next = temp_count;

end


// =========================================================
// Sequential Registers
// =========================================================

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        buffer_reg <= 256'd0;

        byte_count <= 6'd0;

        active_reg <= 1'b0;

        last_seen_reg <= 1'b0;

    end
    else begin

        buffer_reg <= buffer_next;

        byte_count <= byte_count_next;

        active_reg <= active_next;

        last_seen_reg <= last_seen_next;

    end

end


// =========================================================
// Busy
// =========================================================

assign o_busy = active_reg;


endmodule