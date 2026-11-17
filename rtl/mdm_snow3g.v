// SNOW 3G (TS 35.216). After 32 initialization clocks and one discard,
// valid && advance yields one 32-bit word per clock. State freezes on stall.
// key and iv are standard MSB-first byte strings, iv={IV3,IV2,IV1,IV0}.
module mdm_snow3g (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         start,
    input  wire [127:0] key,
    input  wire [127:0] iv,
    input  wire         advance,
    output wire         valid,
    output wire [31:0]  word_out
);
    `include "mdm_sboxes.vh"

    function automatic [7:0] mulx(input [7:0] x, input [7:0] poly);
        mulx = {x[6:0],1'b0} ^ (x[7] ? poly : 8'b0);
    endfunction

    function automatic [31:0] s_transform(input [31:0] w, input use_sq);
        reg [7:0] a,b,c,d,poly;
        begin
            if (use_sq) begin
                a = snow_sq(w[31:24]);
                b = snow_sq(w[23:16]);
                c = snow_sq(w[15:8]);
                d = snow_sq(w[7:0]);
                poly = 8'h69;
            end else begin
                a = aes_sbox(w[31:24]);
                b = aes_sbox(w[23:16]);
                c = aes_sbox(w[15:8]);
                d = aes_sbox(w[7:0]);
                poly = 8'h1b;
            end
            s_transform = {
                mulx(a,poly) ^ b ^ c ^ mulx(d,poly) ^ d,
                mulx(a,poly) ^ a ^ mulx(b,poly) ^ c ^ d,
                a ^ mulx(b,poly) ^ b ^ mulx(c,poly) ^ d,
                a ^ b ^ mulx(c,poly) ^ c ^ mulx(d,poly)
            };
        end
    endfunction

    localparam [1:0] IDLE=0, INIT=1, DISCARD=2, WORK=3;
    reg [1:0] state, next_state;
    reg [5:0] init_count;
    reg [31:0] s [0:15];
    reg [31:0] r1,r2,r3;
    wire [31:0] f = (s[15] + r1) ^ r2;
    wire [31:0] next_r1 = r2 + (r3 ^ s[5]);
    wire [31:0] feedback = {s[0][23:0],8'b0} ^ snow_mulalpha(s[0][31:24]) ^
                           s[2] ^ {8'b0,s[11][31:8]} ^ snow_divalpha(s[11][7:0]) ^
                           ((state == INIT) ? f : 32'b0);
    integer i;

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
            next_state = INIT;
        end else begin
            case (state)
                IDLE: next_state = IDLE;
                INIT: if (init_count == 31) next_state = DISCARD;
                DISCARD: next_state = WORK;
                WORK: next_state = WORK;
                default: next_state = IDLE;
            endcase
        end
    end

    // FSM section 3: outputs and separate datapath registers.
    assign valid = (state == WORK);
    assign word_out = f ^ s[0];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_count <= 0;
            r1 <= 0;
            r2 <= 0;
            r3 <= 0;
            for (i=0;
                 i<16;
                 i=i+1)
                s[i] <= 0;
        end else if (start) begin
            s[15] <= key[127:96] ^ iv[31:0];
            s[14] <= key[95:64];
            s[13] <= key[63:32];
            s[12] <= key[31:0] ^ iv[63:32];
            s[11] <= ~key[127:96];
            s[10] <= ~key[95:64] ^ iv[95:64];
            s[9] <= ~key[63:32] ^ iv[127:96];
            s[8] <= ~key[31:0];
            s[7] <= key[127:96];
            s[6] <= key[95:64];
            s[5] <= key[63:32];
            s[4] <= key[31:0];
            s[3] <= ~key[127:96];
            s[2] <= ~key[95:64];
            s[1] <= ~key[63:32];
            s[0] <= ~key[31:0];
            r1 <= 0;
            r2 <= 0;
            r3 <= 0;
            init_count <= 0;
        end else if (state == INIT || state == DISCARD || (state == WORK && advance)) begin
            r1 <= next_r1;
            r2 <= s_transform(r1,1'b0);
            r3 <= s_transform(r2,1'b1);
            for (i=0;
                 i<15;
                 i=i+1)
                s[i] <= s[i+1];
            s[15] <= feedback;
            if (state == INIT && init_count != 31)
                init_count <= init_count + 1'b1;
        end
    end
endmodule
