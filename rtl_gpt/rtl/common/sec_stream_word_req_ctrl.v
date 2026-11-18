module sec_stream_word_req_ctrl (
    input  wire         clk,
    input  wire         rst_n,

    input  wire         i_start,
    output wire         o_start_ready,

    input  wire [15:0]  i_block_num,

    output wire        o_word_req,
    input  wire        i_word_req_ready,

    output wire        o_busy,
    output wire        o_done
);

    reg        active_reg;

    reg [17:0] remaining_words;

    reg        done_reg;

    wire req_fire;

    assign o_start_ready =
        !active_reg;

    assign o_word_req =
        active_reg &&
        (remaining_words != 18'd0);

    assign req_fire =
        o_word_req && i_word_req_ready;

    assign o_busy =
        active_reg;

    assign o_done =
        done_reg;


    always @(posedge clk or negedge rst_n) begin

        if (!rst_n) begin

            active_reg <= 1'b0;

            remaining_words <= 18'd0;

            done_reg <= 1'b0;

        end
        else begin

            done_reg <= 1'b0;

            if (i_start && o_start_ready) begin

                remaining_words <= {
                    i_block_num,
                    2'b00
                };

                if (i_block_num == 16'd0) begin

                    active_reg <= 1'b0;

                    done_reg <= 1'b1;

                end
                else begin

                    active_reg <= 1'b1;

                end

            end
            else if (req_fire) begin

                remaining_words <=
                    remaining_words - 18'd1;

                if (remaining_words == 18'd1) begin

                    active_reg <= 1'b0;

                    done_reg <= 1'b1;

                end

            end

        end

    end

endmodule