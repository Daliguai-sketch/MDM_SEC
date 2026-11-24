// Integrity lane: 128-EIA1, EIA2, EIA3 and EIA0. Input is MSB-first
// 32-bit words, and all byte counts are 16 bits.
module mdm_integrity #(
    parameter integer AES_LOW_AREA=1,
    parameter integer BALANCED_TIMING_OPT=1
) (
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
    output reg  [31:0]  mac,
    output reg          done
);
    localparam [3:0] IDLE=0, AES_L_REQ=1, AES_L_WAIT=2, AES_COLLECT=3,
                     AES_BLOCK_REQ=4, AES_BLOCK_WAIT=5, SNOW_KEYS=6,
                     SNOW_DATA=7, SNOW_FINAL=8, ZUC_FIRST=9,
                     ZUC_SECOND=10, ZUC_DATA=11;
    reg [3:0] state, next_state;
    reg [127:0] key_q;
    reg [31:0] count_q;
    reg [4:0] bearer_q;
    reg dir_q;
    reg [15:0] length_q,left;
    wire [15:0] bytes_now = (left>=16'd4) ? 16'd4 : left;
    wire [31:0] mask = (bytes_now==4) ? 32'hffffffff :
                       (bytes_now==3) ? 32'hffffff00 :
                       (bytes_now==2) ? 32'hffff0000 :
                       (bytes_now==1) ? 32'hff000000 : 32'b0;
    wire [31:0] data_masked = in_data & mask;
    wire [31:0] fresh = {bearer,27'b0};
    wire [127:0] int_iv = {count,fresh,count ^ {direction,31'b0},fresh ^ {16'b0,direction,15'b0}};
    wire snow_valid,zuc_valid;
    wire [31:0] snow_word,zuc_word;
    wire snow_advance = (state==SNOW_KEYS) && snow_valid;
    wire zuc_advance = ((state==ZUC_FIRST || state==ZUC_SECOND) && zuc_valid) ||
                       ((state==ZUC_DATA) && in_valid && in_ready);
    mdm_snow3g u_snow (
        .clk(clk), .rst_n(rst_n), .start(start && alg==1), .key(key), .iv(int_iv),
        .advance(snow_advance), .valid(snow_valid), .word_out(snow_word)
    );
    mdm_zuc u_zuc (
        .clk(clk), .rst_n(rst_n), .start(start && alg==3), .key(key), .iv(int_iv),
        .advance(zuc_advance), .valid(zuc_valid), .word_out(zuc_word)
    );

    reg [127:0] aes_input,block,chain,k1,k2;
    reg [15:0] used;
    reg final_block;
    wire aes_start = !start && (state==AES_L_REQ || state==AES_BLOCK_REQ);
    wire aes_ready,aes_busy,aes_done;
    wire [127:0] aes_out;
    wire [127:0] aes_block_in = (state==AES_L_REQ) ? 128'b0 : aes_input;
    // Both independent lanes select balanced-opt for AES_LOW_AREA=2.
    // BALANCED_TIMING_OPT is a legacy guard; mode 2 rejects 0 (retired core).
    mdm_aes128 #(.AES_LOW_AREA(AES_LOW_AREA), .BALANCED_TIMING_OPT(BALANCED_TIMING_OPT)) u_aes (
        .clk(clk), .rst_n(rst_n), .start(aes_start), .ready(aes_ready),
        .key(key_q), .block_in(aes_block_in), .busy(aes_busy), .done(aes_done), .block_out(aes_out)
    );
    function automatic [127:0] cmac_double(input [127:0] x);
        cmac_double = {x[126:0],1'b0} ^ (x[127] ? 128'h87 : 128'b0);
    endfunction
    reg [127:0] placed;
    wire [15:0] used_after = used+bytes_now;
    // Except for the final partial word, all inputs are 4-byte words.
    // Thus used is always 0, 4, 8 or 12 while collecting a CMAC block.
    // A word-aligned mux avoids four independent byte insertion crossbars.
    always @* begin
        case (used[3:2])
            2'd0: placed = {data_masked,96'b0};
            2'd1: placed = {32'b0,data_masked,64'b0};
            2'd2: placed = {64'b0,data_masked,32'b0};
            2'd3: placed = {96'b0,data_masked};
            default: placed = 128'b0;
        endcase
    end
    wire [127:0] assembled = block | placed;
    wire [127:0] pad_bit = 128'h80000000000000000000000000000000 >> {used_after[3:0],3'b0};
    wire [127:0] padded = assembled | ((used_after<16'd16) ? pad_bit : 128'b0);

    // One combinational GF(2^64) multiplier is shared by the P and Q steps.
    function automatic [63:0] gf64_mul(input [63:0] x,input [63:0] y);
        reg [63:0] t,v;
        integer i;
        begin
            t = 0;
            v = x;
            for (i=0;
                 i<64;
                 i=i+1) begin
                if (y[i])
                    t = t^v;
                v = {v[62:0],1'b0} ^ (v[63] ? 64'h1b : 64'b0);
            end
            gf64_mul = t;
        end
    endfunction
    reg [2:0] snow_index;
    reg [63:0] p,q,eval_reg;
    reg [31:0] snow_z5,half_word;
    reg half_full;
    wire [63:0] snow_message = half_full ? {half_word,data_masked} : {data_masked,32'b0};
    wire [63:0] mul_x = (state==SNOW_FINAL) ? (eval_reg ^ {45'b0,length_q,3'b0}) :
                                                 (eval_reg ^ snow_message);
    wire [63:0] mul_y = (state==SNOW_FINAL) ? q : p;
    wire [63:0] mul_result = gf64_mul(mul_x,mul_y);

    reg [31:0] zcur,znext,zacc;
    reg [31:0] zdata_acc,final_window;
    reg [63:0] zwindow;
    wire [31:0] bits_now = {13'b0,bytes_now,3'b0};
    integer bitno;
    always @* begin
        zwindow = {zcur,znext};
        zdata_acc = zacc;
        for (bitno=0;
             bitno<32;
             bitno=bitno+1)
            if (bitno < bits_now && in_data[31-bitno])
                zdata_acc = zdata_acc ^ zwindow[63-bitno -: 32];
        if (bytes_now==4)
            final_window = znext;
        else
            final_window = (zcur << bits_now) | (znext >> (32-bits_now));
    end

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
            case (alg)
                2'd0: next_state = IDLE;
                2'd1: next_state = SNOW_KEYS;
                2'd2: next_state = AES_L_REQ;
                2'd3: next_state = ZUC_FIRST;
                default: next_state = IDLE;
            endcase
        end else begin
            case (state)
                IDLE: next_state = IDLE;
                AES_L_REQ: if (aes_ready) next_state = AES_L_WAIT;
                AES_L_WAIT: if (aes_done) begin
                    if (length_q==0)
                        next_state = AES_BLOCK_REQ;
                    else
                        next_state = AES_COLLECT;
                end
                AES_COLLECT: if (in_valid && in_ready && (left<=4 || used_after==16))
                    next_state = AES_BLOCK_REQ;
                AES_BLOCK_REQ: if (aes_ready) next_state = AES_BLOCK_WAIT;
                AES_BLOCK_WAIT: if (aes_done) begin
                    if (final_block)
                        next_state = IDLE;
                    else
                        next_state = AES_COLLECT;
                end
                SNOW_KEYS: if (snow_valid && snow_index==4) begin
                    if (length_q==0)
                        next_state = SNOW_FINAL;
                    else
                        next_state = SNOW_DATA;
                end
                SNOW_DATA: if (in_valid && in_ready && left<=4) next_state = SNOW_FINAL;
                SNOW_FINAL: next_state = IDLE;
                ZUC_FIRST: if (zuc_valid) next_state = ZUC_SECOND;
                ZUC_SECOND: if (zuc_valid) begin
                    if (length_q==0)
                        next_state = IDLE;
                    else
                        next_state = ZUC_DATA;
                end
                ZUC_DATA: if (in_valid && in_ready && left<=4) next_state = IDLE;
                default: next_state = IDLE;
            endcase
        end
    end

    // FSM section 3: output logic and independently clocked datapath.
    assign in_ready = (state==AES_COLLECT || state==SNOW_DATA ||
                      (state==ZUC_DATA && zuc_valid));
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_q <= 0;
            count_q <= 0;
            bearer_q <= 0;
            dir_q <= 0;
            length_q <= 0;
            left <= 0;
            mac <= 0;
            done <= 0;
            aes_input <= 0;
            block <= 0;
            chain <= 0;
            k1 <= 0;
            k2 <= 0;
            used <= 0;
            final_block <= 0;
            snow_index <= 0;
            p <= 0;
            q <= 0;
            eval_reg <= 0;
            snow_z5 <= 0;
            half_word <= 0;
            half_full <= 0;
            zcur <= 0;
            znext <= 0;
            zacc <= 0;
        end else begin
            done <= 0;
            if (start) begin
                key_q <= key;
                count_q <= count;
                bearer_q <= bearer;
                dir_q <= direction;
                length_q <= length;
                left <= length;
                mac <= 0;
                chain <= 0;
                block <= 0;
                snow_index <= 0;
                p <= 0;
                q <= 0;
                eval_reg <= 0;
                half_full <= 0;
                zcur <= 0;
                znext <= 0;
                zacc <= 0;
                if (alg==2'd0)
                    done <= 1;
            end else begin
                case (state)
                    AES_L_WAIT: if (aes_done) begin
                        k1 <= cmac_double(aes_out);
                        k2 <= cmac_double(cmac_double(aes_out));
                        block <= {count_q,bearer_q,dir_q,26'b0,64'b0};
                        used <= 8;
                        if (length_q==0) begin
                            aes_input <= {count_q,bearer_q,dir_q,26'b0,8'h80,56'b0} ^
                                         cmac_double(cmac_double(aes_out));
                            final_block <= 1;
                        end
                    end
                    AES_COLLECT: if (in_valid && in_ready) begin
                        if (left<=4) begin
                            if (used_after==16)
                                aes_input <= assembled ^ k1 ^ chain;
                            else
                                aes_input <= padded ^ k2 ^ chain;
                            final_block <= 1;
                            left <= 0;
                        end else begin
                            left <= left-16'd4;
                            if (used_after==16) begin
                                aes_input <= assembled ^ chain;
                                final_block <= 0;
                            end else begin
                                block <= assembled;
                                used <= used_after;
                            end
                        end
                    end
                    AES_BLOCK_WAIT: if (aes_done) begin
                        if (final_block) begin
                            mac <= aes_out[127:96];
                            done <= 1;
                        end else begin
                            chain <= aes_out;
                            block <= 0;
                            used <= 0;
                        end
                    end
                    SNOW_KEYS: if (snow_valid) begin
                        case (snow_index)
                            0: p[63:32] <= snow_word;
                            1: p[31:0] <= snow_word;
                            2: q[63:32] <= snow_word;
                            3: q[31:0] <= snow_word;
                            4: snow_z5 <= snow_word;
                            default: ;
                        endcase
                        if (snow_index!=4)
                            snow_index <= snow_index+1'b1;
                    end
                    SNOW_DATA: if (in_valid && in_ready) begin
                        if (!half_full && left>4) begin
                            half_word <= data_masked;
                            half_full <= 1;
                        end else begin
                            eval_reg <= mul_result;
                            half_full <= 0;
                        end
                        if (left<=4)
                            left <= 0;
                        else
                            left <= left-16'd4;
                    end
                    SNOW_FINAL: begin
                        mac <= mul_result[63:32] ^ snow_z5;
                        done <= 1;
                    end
                    ZUC_FIRST: if (zuc_valid)
                        zcur <= zuc_word;
                    ZUC_SECOND: if (zuc_valid) begin
                        znext <= zuc_word;
                        if (length_q==0) begin
                            mac <= zcur ^ zuc_word;
                            done <= 1;
                        end
                    end
                    ZUC_DATA: if (in_valid && in_ready) begin
                        if (left<=4) begin
                            mac <= zdata_acc ^ final_window ^ zuc_word;
                            left <= 0;
                            done <= 1;
                        end else begin
                            zacc <= zdata_acc;
                            zcur <= znext;
                            znext <= zuc_word;
                            left <= left-16'd4;
                        end
                    end
                    default: ;
                endcase
            end
        end
    end
endmodule
