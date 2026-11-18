module sec_stream_packer_32to128 (
    input  wire         clk,
    input  wire         rst_n,

    // New packet / algorithm switch clear
    input  wire         i_clear,

    // 32-bit input stream
    input  wire [31:0]  i_word,
    input  wire         i_word_vld,
    output wire         o_word_ready,

    // 128-bit output stream
    output wire [127:0] o_stream,
    output wire         o_stream_vld,
    input  wire         i_stream_ready
);

    reg [95:0] partial_reg;

    reg [1:0]  word_count;

    reg [127:0] stream_reg;
    reg         stream_valid_reg;

    wire input_fire;
    wire output_fire;

    /*
     * A new word can be accepted when:
     *
     * 1. Output register is empty.
     * 2. Current output is being consumed.
     *
     * If output is stalled, input is blocked.
     */

    assign o_word_ready =
        !i_clear &&
        (!stream_valid_reg || i_stream_ready);

    assign input_fire =
        i_word_vld && o_word_ready;

    assign output_fire =
        stream_valid_reg && i_stream_ready;

    assign o_stream =
        stream_reg;

    assign o_stream_vld =
        stream_valid_reg;


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            partial_reg       <= 96'b0;
            word_count        <= 2'b0;

            stream_reg        <= 128'b0;
            stream_valid_reg  <= 1'b0;

        end
        else if (i_clear) begin

            partial_reg       <= 96'b0;
            word_count        <= 2'b0;

            stream_reg        <= 128'b0;
            stream_valid_reg  <= 1'b0;

        end
        else begin

            /*
             * Output consumption
             */

            if (output_fire)
                stream_valid_reg <= 1'b0;


            /*
             * Input word collection
             */

            if (input_fire) begin

                case (word_count)

                    2'd0: begin

                        partial_reg[95:64] <= i_word;

                        word_count <= 2'd1;

                    end


                    2'd1: begin

                        partial_reg[63:32] <= i_word;

                        word_count <= 2'd2;

                    end


                    2'd2: begin

                        partial_reg[31:0] <= i_word;

                        word_count <= 2'd3;

                    end


                    2'd3: begin

                        /*
                         * Fourth word completes one
                         * 128-bit Keystream block.
                         */

                        stream_reg <= {
                            partial_reg[95:0],
                            i_word
                        };

                        stream_valid_reg <= 1'b1;

                        word_count <= 2'd0;

                    end

                    default: begin

                        word_count <= 2'd0;

                    end

                endcase

            end

        end

    end

endmodule