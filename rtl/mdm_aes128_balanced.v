// Area-optimized five-cycle AES-128. Two cascaded rounds are retained per
// clock; MixColumns uses a shared-XOR linear network. See the spec for PPA
// limits, proof, and the source/license of the MixColumns circuit.
// A request is accepted on start && ready. The final edge may also accept
// the next request. This is Verilog-2005 RTL, not SystemVerilog.
module mdm_aes128_balanced (
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
    function automatic [7:0] xtime(input [7:0] x);
        xtime = {x[6:0], 1'b0} ^ (x[7] ? 8'h1b : 8'h00);
    endfunction

    localparam IDLE = 1'b0;
    localparam COMPUTE = 1'b1;
    reg state, next_state;
    reg [127:0] round_state, key_reg;
    reg [7:0] rcon;
    reg [2:0] pair;
    wire [127:0] initial_state, key1, key2, round1, round2;

    // Follow the Python model's initial AddRoundKey, key expansion and
    // round stages, while keeping all logic combinational between registers.
    mdm_aes_balanced_add_round_key u_initial_add_round_key (
        .state_in(block_in), .round_key(key), .state_out(initial_state)
    );
    mdm_aes_balanced_key_expand1 u_key_expand1 (
        .key_in(key_reg), .rcon(rcon), .key_out(key1)
    );
    mdm_aes_balanced_key_expand2 u_key_expand2 (
        .key_in(key_reg), .key1(key1), .rcon(xtime(rcon)), .key_out(key2)
    );
    mdm_aes_balanced_round #(.MAY_SKIP_MIX(0)) u_round1 (
        .state_in(round_state), .round_key(key1), .last_round(1'b0), .state_out(round1)
    );
    mdm_aes_balanced_round #(.MAY_SKIP_MIX(1)) u_round2 (
        .state_in(round1), .round_key(key2), .last_round(pair == 3'd4), .state_out(round2)
    );

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
            IDLE: if (start) next_state = COMPUTE;
            COMPUTE: if (pair == 3'd4 && !start) next_state = IDLE;
            default: next_state = IDLE;
        endcase
    end

    // FSM section 3: outputs and independently clocked datapath registers.
    assign busy = (state == COMPUTE);
    assign ready = (state == IDLE) || (state == COMPUTE && pair == 3'd4);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            done <= 1'b0;
            block_out <= 0;
            round_state <= 0;
            key_reg <= 0;
            rcon <= 0;
            pair <= 0;
        end else begin
            done <= 1'b0;
            if (state == COMPUTE) begin
                if (pair == 3'd4) begin
                    block_out <= round2;
                    done <= 1'b1;
                end else begin
                    round_state <= round2;
                    key_reg <= key2;
                    rcon <= xtime(xtime(rcon));
                    pair <= pair + 1'b1;
                end
            end
            if (start && ready) begin
                round_state <= initial_state;
                key_reg <= key;
                rcon <= 8'h01;
                pair <= 0;
            end
        end
    end
endmodule
