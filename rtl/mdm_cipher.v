// Confidentiality lane: 3GPP 128-EEA1/2/3 and EEA0 bypass.
// Internal streaming data is 32 bits, MSB first. All byte counts are 16 bits.
module mdm_cipher (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [1:0]   alg,
    input  wire [127:0] key,
    input  wire [31:0]  count,
    input  wire [4:0]   bearer,
    input  wire         direction,
    input  wire [15:0]  length,
    input  wire         in_valid,
    output wire         in_ready,
    input  wire [31:0]  in_data,
    output wire         out_valid,
    input  wire         out_ready,
    output wire [31:0]  out_data,
    output wire [15:0]  out_bytes,
    output reg          done
);
    localparam IDLE = 1'b0;
    localparam ACTIVE = 1'b1;
    reg state, next_state;
    wire active = (state == ACTIVE);
    reg [1:0] alg_q;
    reg [127:0] key_q;
    reg [31:0] count_q;
    reg [4:0] bearer_q;
    reg dir_q;
    reg [15:0] left, length_q, issued;
    reg [63:0] aes_counter;
    wire [127:0] stream_iv = {count,bearer,direction,26'b0,count,bearer,direction,26'b0};
    wire snow_valid,zuc_valid;
    wire [31:0] snow_word,zuc_word;
    wire transfer = out_valid && out_ready;

    mdm_snow3g u_snow (
        .clk(clk), .rst_n(rst_n), .start(start && alg==2'd1 && length!=0),
        .key(key), .iv(stream_iv), .advance(transfer && alg_q==2'd1),
        .valid(snow_valid), .word_out(snow_word)
    );
    mdm_zuc u_zuc (
        .clk(clk), .rst_n(rst_n), .start(start && alg==2'd3 && length!=0),
        .key(key), .iv(stream_iv), .advance(transfer && alg_q==2'd3),
        .valid(zuc_valid), .word_out(zuc_word)
    );

    wire aes_ready,aes_busy,aes_done;
    wire [127:0] aes_out;
    reg [127:0] ks0,ks1;
    reg v0,v1;
    reg [1:0] ks_index;
    wire pop_block = transfer && ((ks_index==2'd3) || left<=16'd4);
    wire [3:0] occupied = {3'b0,v0}+{3'b0,v1}+{3'b0,aes_busy}+{3'b0,aes_done};
    wire [3:0] occupied_after_pop = occupied-((pop_block && v0) ? 4'd1 : 4'd0);
    wire aes_start = active && !start && alg_q==2'd2 && aes_ready && issued<length_q &&
                     occupied_after_pop<4'd2;
    wire [127:0] aes_in = {count_q,bearer_q,dir_q,26'b0,aes_counter};
    mdm_aes128 u_aes (
        .clk(clk), .rst_n(rst_n), .start(aes_start), .ready(aes_ready),
        .key(key_q), .block_in(aes_in), .busy(aes_busy), .done(aes_done), .block_out(aes_out)
    );

    wire [31:0] aes_word = ks0[127-32*ks_index -: 32];
    wire available = (alg_q==0) ? 1'b1 :
                     (alg_q==1) ? snow_valid : (alg_q==2) ? v0 : zuc_valid;
    wire [31:0] stream_word = (alg_q==0) ? 32'b0 :
                              (alg_q==1) ? snow_word : (alg_q==2) ? aes_word : zuc_word;
    wire [31:0] byte_mask = (out_bytes==4) ? 32'hffffffff :
                            (out_bytes==3) ? 32'hffffff00 :
                            (out_bytes==2) ? 32'hffff0000 :
                            (out_bytes==1) ? 32'hff000000 : 32'b0;

    // FSM section 1: state register only.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // FSM section 2: next-state logic only.
    always @* begin
        next_state = state;
        if (start) begin
            if (length == 0)
                next_state = IDLE;
            else
                next_state = ACTIVE;
        end else begin
            case (state)
                IDLE: next_state = IDLE;
                ACTIVE: if (transfer && left<=16'd4) next_state = IDLE;
                default: next_state = IDLE;
            endcase
        end
    end

    // FSM section 3: outputs and separate datapath/FIFO registers.
    assign out_bytes = (left>=16'd4) ? 16'd4 : left;
    assign in_ready = active && out_ready && available;
    assign out_valid = active && in_valid && available;
    assign out_data = (in_data ^ stream_word) & byte_mask;

    // Two entries reserve space for the current and one prefetched AES block.
    reg [127:0] n_ks0,n_ks1;
    reg n_v0,n_v1;
    reg [1:0] n_index;
    always @* begin
        n_ks0 = ks0;
        n_ks1 = ks1;
        n_v0 = v0;
        n_v1 = v1;
        n_index = ks_index;
        if (transfer && alg_q==2'd2) begin
            if (pop_block) begin
                n_ks0 = ks1;
                n_v0 = v1;
                n_v1 = 0;
                n_index = 0;
            end else begin
                n_index = ks_index+1'b1;
            end
        end
        if (aes_done && active && alg_q==2'd2) begin
            if (!n_v0) begin
                n_ks0 = aes_out;
                n_v0 = 1;
                n_index = 0;
            end else if (!n_v1) begin
                n_ks1 = aes_out;
                n_v1 = 1;
            end
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            alg_q <= 0;
            key_q <= 0;
            count_q <= 0;
            bearer_q <= 0;
            dir_q <= 0;
            left <= 0;
            length_q <= 0;
            issued <= 0;
            aes_counter <= 0;
            done <= 0;
            ks0 <= 0;
            ks1 <= 0;
            v0 <= 0;
            v1 <= 0;
            ks_index <= 0;
        end else begin
            done <= 0;
            ks0 <= n_ks0;
            ks1 <= n_ks1;
            v0 <= n_v0;
            v1 <= n_v1;
            ks_index <= n_index;
            if (aes_start) begin
                // Saturate at length instead of wrapping for length=65535.
                if (length_q-issued<=16'd16)
                    issued <= length_q;
                else
                    issued <= issued+16'd16;
                aes_counter <= aes_counter+1'b1;
            end
            if (transfer) begin
                if (left<=16'd4) begin
                    left <= 0;
                    done <= 1;
                end else begin
                    left <= left-16'd4;
                end
            end
            if (start) begin
                alg_q <= alg;
                key_q <= key;
                count_q <= count;
                bearer_q <= bearer;
                dir_q <= direction;
                left <= length;
                length_q <= length;
                issued <= 0;
                aes_counter <= 0;
                v0 <= 0;
                v1 <= 0;
                ks_index <= 0;
                if (length==0)
                    done <= 1;
            end
        end
    end
endmodule
