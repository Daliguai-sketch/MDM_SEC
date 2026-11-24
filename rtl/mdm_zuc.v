// ZUC-128 (TS 35.221). After 32 initialization clocks and one discard,
// valid && advance yields one 32-bit word per clock. State freezes on stall.
module mdm_zuc (
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

    function automatic [14:0] d_const(input integer n);
        begin
            case (n)
                0: d_const=15'h44d7;
                1: d_const=15'h26bc;
                2: d_const=15'h626b;
                3: d_const=15'h135e;
                4: d_const=15'h5789;
                5: d_const=15'h35e2;
                6: d_const=15'h7135;
                7: d_const=15'h09af;
                8: d_const=15'h4d78;
                9: d_const=15'h2f13;
                10: d_const=15'h6bc4;
                11: d_const=15'h1af1;
                12: d_const=15'h5e26;
                13: d_const=15'h3c4d;
                14: d_const=15'h789a;
                default: d_const=15'h47ac;
            endcase
        end
    endfunction
    function automatic [30:0] add31(input [30:0] a, input [30:0] b);
        reg [31:0] t;
        begin
            t = {1'b0,a}+{1'b0,b};
            add31 = t[30:0]+{30'b0,t[31]};
        end
    endfunction
    function automatic [30:0] rot31(input [30:0] a, input integer n);
        rot31 = (a << n) | (a >> (31-n));
    endfunction
    function automatic [31:0] rot32(input [31:0] a, input integer n);
        rot32 = (a << n) | (a >> (32-n));
    endfunction
    function automatic [31:0] linear1(input [31:0] a);
        linear1 = a^rot32(a,2)^rot32(a,10)^rot32(a,18)^rot32(a,24);
    endfunction
    function automatic [31:0] linear2(input [31:0] a);
        linear2 = a^rot32(a,8)^rot32(a,14)^rot32(a,22)^rot32(a,30);
    endfunction
    function automatic [31:0] subword(input [31:0] a);
        subword = {zuc_s0(a[31:24]),zuc_s1(a[23:16]),zuc_s0(a[15:8]),zuc_s1(a[7:0])};
    endfunction

    localparam [1:0] IDLE=0, INIT=1, DISCARD=2, WORK=3;
    reg [1:0] state, next_state;
    reg [5:0] init_count;
    reg [30:0] s[0:15];
    reg [31:0] r1,r2;
    wire [31:0] x0 = {s[15][30:15],s[14][15:0]};
    wire [31:0] x1 = {s[11][15:0],s[9][30:15]};
    wire [31:0] x2 = {s[7][15:0],s[5][30:15]};
    wire [31:0] x3 = {s[2][15:0],s[0][30:15]};
    wire [31:0] w = (x0 ^ r1)+r2;
    wire [31:0] w1 = r1+x1;
    wire [31:0] w2 = r2^x2;
    wire [31:0] new_r1 = subword(linear1({w1[15:0],w2[31:16]}));
    wire [31:0] new_r2 = subword(linear2({w2[15:0],w1[31:16]}));
    wire [30:0] f0 = add31(s[0],rot31(s[0],8));
    wire [30:0] f1 = add31(f0,rot31(s[4],20));
    wire [30:0] f2 = add31(f1,rot31(s[10],21));
    wire [30:0] f3 = add31(f2,rot31(s[13],17));
    wire [30:0] f4 = add31(f3,rot31(s[15],15));
    wire [30:0] f5 = add31(f4,(state == INIT) ? w[31:1] : 31'b0);
    wire [30:0] feedback = (f5 == 0) ? 31'h7fffffff : f5;
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
    assign word_out = w^x3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            init_count <= 0;
            r1 <= 0;
            r2 <= 0;
            for (i=0;
                 i<16;
                 i=i+1)
                s[i] <= 0;
        end else if (start) begin
            for (i=0;
                 i<16;
                 i=i+1)
                s[i] <= {key[127-8*i -: 8],d_const(i),iv[127-8*i -: 8]};
            r1 <= 0;
            r2 <= 0;
            init_count <= 0;
        end else if (state == INIT || state == DISCARD || (state == WORK && advance)) begin
            r1 <= new_r1;
            r2 <= new_r2;
            for (i=0;
                 i<15;
                 i=i+1)
                s[i] <= s[i+1];
            s[15] <= feedback;
            if (state == INIT && init_count != 31)
                init_count <= init_count+1'b1;
        end
    end
endmodule
