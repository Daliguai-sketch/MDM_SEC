// Low-area AES-128: four S-boxes are shared by the key schedule and the
// state datapath. One key cycle plus four column cycles per round gives
// a 50-cycle block latency and initiation interval.
module mdm_aes128_serial (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    output wire         ready,
    input  wire [127:0] key,
    input  wire [127:0] block_in,
    output wire         busy,
    output reg          done,
    output reg  [127:0] block_out
);
    localparam [1:0] IDLE=0, ROUND_KEY=1, ROUND_DATA=2;
    reg [1:0] state,next_state;
    reg [127:0] round_state,key_reg;
    reg [95:0] partial_state;
    reg [7:0] rcon;
    reg [3:0] round;
    reg [1:0] column;

    wire [127:0] shifted_state,next_key;
    wire [31:0] shifted_column,key_column,sbox_in,sbox_out,mixed_column;
    wire [31:0] selected_column,round_column;
    wire final_cycle = (state==ROUND_DATA) && (column==2'd3) && (round==4'd9);
    assign shifted_column = shifted_state[127-32*column -: 32];
    assign key_column = key_reg[127-32*column -: 32];
    assign sbox_in = (state==ROUND_KEY) ? {key_reg[23:0],key_reg[31:24]} : shifted_column;
    assign selected_column = (round==4'd9) ? sbox_out : mixed_column;

    mdm_aes_shift_rows u_shift_rows (.state_in(round_state), .state_out(shifted_state));
    mdm_aes_subbytes4 u_subbytes (.data_in(sbox_in), .data_out(sbox_out));
    mdm_aes_key_expand u_key_expand (.key_in(key_reg), .subword(sbox_out),
                                     .rcon(rcon), .key_out(next_key));
    mdm_aes_mix_column u_mix_column (.data_in(sbox_out), .data_out(mixed_column));
    mdm_aes_add_round_key u_add_round_key (.data_in(selected_column),
                                          .round_key(key_column), .data_out(round_column));

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
        case (state)
            IDLE: if (start) next_state = ROUND_KEY;
            ROUND_KEY: next_state = ROUND_DATA;
            ROUND_DATA: if (column==2'd3) begin
                if (round!=4'd9 || start)
                    next_state = ROUND_KEY;
                else
                    next_state = IDLE;
            end
            default: next_state = IDLE;
        endcase
    end

    // FSM section 3: outputs and separate datapath registers.
    assign busy = (state!=IDLE);
    assign ready = (state==IDLE) || final_cycle;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            round_state <= 0;
            key_reg <= 0;
            partial_state <= 0;
            rcon <= 0;
            round <= 0;
            column <= 0;
            block_out <= 0;
            done <= 0;
        end else begin
            done <= 0;
            if (state==ROUND_KEY) begin
                key_reg <= next_key;
                rcon <= {rcon[6:0],1'b0} ^ ({8{rcon[7]}} & 8'h1b);
                column <= 0;
            end
            if (state==ROUND_DATA) begin
                case (column)
                    2'd0: partial_state[95:64] <= round_column;
                    2'd1: partial_state[63:32] <= round_column;
                    2'd2: partial_state[31:0] <= round_column;
                    2'd3: begin
                        if (round==4'd9) begin
                            block_out <= {partial_state,round_column};
                            done <= 1;
                        end else begin
                            round_state <= {partial_state,round_column};
                            round <= round+1'b1;
                        end
                    end
                    default: ;
                endcase
                if (column!=2'd3)
                    column <= column+1'b1;
            end
            // The final edge may retire one block and accept the next one.
            if (start && ready) begin
                round_state <= block_in ^ key;
                key_reg <= key;
                rcon <= 8'h01;
                round <= 0;
                column <= 0;
            end
        end
    end
endmodule
