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
    `include "mdm_sboxes.vh"
    `include "mdm_aes_mix_balanced.vh"

    function automatic [7:0] xtime(input [7:0] x);
        xtime = {x[6:0], 1'b0} ^ (x[7] ? 8'h1b : 8'h00);
    endfunction

    function automatic [127:0] next_key(input [127:0] k, input [7:0] rc);
        reg [31:0] a, b, c, d, t;
        begin
            a = k[127:96];
            b = k[95:64];
            c = k[63:32];
            d = k[31:0];
            t = {aes_sbox(d[23:16]), aes_sbox(d[15:8]),
                 aes_sbox(d[7:0]), aes_sbox(d[31:24])} ^ {rc, 24'b0};
            a = a ^ t;
            b = b ^ a;
            c = c ^ b;
            d = d ^ c;
            next_key = {a, b, c, d};
        end
    endfunction

    function automatic [127:0] round_fn(input [127:0] x,
                                         input [127:0] rk,
                                         input last_round);
        reg [127:0] y, z;
        integer col, row, src;
        begin
            y = 0;
            for (col = 0;
                 col < 4;
                 col = col + 1) begin
                for (row = 0;
                     row < 4;
                     row = row + 1) begin
                    src = 4 * ((col + row) % 4) + row;
                    y[127 - 8*(4*col+row) -: 8] = aes_sbox(x[127 - 8*src -: 8]);
                end
            end
            z = y;
            if (!last_round) begin
                for (col = 0;
                     col < 4;
                     col = col + 1) begin
                    z[127 - 32*col -: 32] =
                        aes_mix_column_balanced(y[127 - 32*col -: 32]);
                end
            end
            round_fn = z ^ rk;
        end
    endfunction

    localparam IDLE = 1'b0;
    localparam COMPUTE = 1'b1;
    reg state, next_state;
    reg [127:0] round_state, key_reg;
    reg [7:0] rcon;
    reg [2:0] pair;
    wire [127:0] key1 = next_key(key_reg, rcon);
    // Two-round AES-128 key expansion, factored to shorten the XOR chain.
    // With old words a,b,c,d and key1 words a1,b1,c1,d1:
    // key2={a1^t2, b^t2, c^(a1^t2), d^(b^t2)}. The cancelled
    // terms are identical on both sides in GF(2); each block keeps its own key.
    wire [31:0] t2 = {aes_sbox(key1[23:16]), aes_sbox(key1[15:8]),
                      aes_sbox(key1[7:0]), aes_sbox(key1[31:24])} ^
                     {xtime(rcon), 24'b0};
    wire [31:0] a2 = key1[127:96] ^ t2;
    wire [31:0] b2 = key_reg[95:64] ^ t2;
    wire [31:0] c2 = key_reg[63:32] ^ a2;
    wire [31:0] d2 = key_reg[31:0] ^ b2;
    wire [127:0] key2 = {a2,b2,c2,d2};
    wire [127:0] round1 = round_fn(round_state, key1, 1'b0);
    wire [127:0] round2 = round_fn(round1, key2, pair == 3'd4);

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
                round_state <= block_in ^ key;
                key_reg <= key;
                rcon <= 8'h01;
                pair <= 0;
            end
        end
    end
endmodule
