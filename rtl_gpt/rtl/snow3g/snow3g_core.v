module snow3g_core (
    input  wire         clk,
    input  wire         rst_n,

    // =====================================================
    // Key / IV Configuration
    // =====================================================
    input  wire         i_init,
    output wire         o_init_ready,

    input  wire [127:0] i_key,
    input  wire [127:0] i_iv,

    output wire         o_core_ready,

    // =====================================================
    // Keystream Request
    // =====================================================
    input  wire         i_stream_req,
    output wire         o_stream_req_ready,

    // =====================================================
    // Keystream Output
    // =====================================================
    output wire [31:0]  o_stream,
    output wire         o_stream_vld,
    input  wire         i_stream_ready,

    // =====================================================
    // Status
    // =====================================================
    output wire         o_busy
);

// =========================================================
// FSM
// =========================================================

localparam ST_IDLE    = 2'd0;
localparam ST_INIT    = 2'd1;
localparam ST_DISCARD = 2'd2;
localparam ST_GEN     = 2'd3;

reg [1:0] state;

// =========================================================
// LFSR Registers
// =========================================================

reg [31:0] s [0:15];

// =========================================================
// FSM Registers
// =========================================================

reg [31:0] r1;
reg [31:0] r2;
reg [31:0] r3;

// =========================================================
// Initialization Counter
// =========================================================

reg [5:0] init_cnt;

// =========================================================
// Keystream Output Register
// =========================================================

reg [31:0] stream_reg;
reg stream_valid_reg;

assign o_stream = stream_reg;
assign o_stream_vld = stream_valid_reg;

// =========================================================
// Key / IV Words
// =========================================================

// Python:
// key = [k0,k1,k2,k3]
// iv  = [iv0,iv1,iv2,iv3]

wire [31:0] k0;
wire [31:0] k1;
wire [31:0] k2;
wire [31:0] k3;

wire [31:0] iv0;
wire [31:0] iv1;
wire [31:0] iv2;
wire [31:0] iv3;

assign k0 = i_key[127:96];
assign k1 = i_key[95:64];
assign k2 = i_key[63:32];
assign k3 = i_key[31:0];

assign iv0 = i_iv[127:96];
assign iv1 = i_iv[95:64];
assign iv2 = i_iv[63:32];
assign iv3 = i_iv[31:0];

// =========================================================
// FSM Combinational Logic
// =========================================================

// Python:
// w = ((s15 + r1) & 0xFFFFFFFF) ^ r2
//
// newR1 = r2 + (r3 ^ s5)
// newR2 = S1(r1)
// newR3 = S2(r2)

wire [31:0] w;
wire [31:0] new_r1;
wire [31:0] new_r2;
wire [31:0] new_r3;

assign w =
    (s[15] + r1) ^ r2;

assign new_r1 =
    r2 + (r3 ^ s[5]);

snow3g_s1 u_s1 (
    .i_data(r1),
    .o_data(new_r2)
);

snow3g_s2 u_s2 (
    .i_data(r2),
    .o_data(new_r3)
);

// =========================================================
// MULalpha / DIValpha
// =========================================================

wire [31:0] mulalpha_data;
wire [31:0] divalpha_data;

snow3g_mulalpha u_mulalpha (
    .i_data(s[0][31:24]),
    .o_data(mulalpha_data)
);

snow3g_divalpha u_divalpha (
    .i_data(s[11][7:0]),
    .o_data(divalpha_data)
);

// =========================================================
// LFSR Feedback
// =========================================================

// Python:
//
// t0 = (s0 << 8) & 0xFFFFFF00
// t1 = MULalpha(s0 >> 24)
// t2 = (s11 >> 8) & 0x00FFFFFF
// t3 = DIValpha(s11 & 0xFF)
//
// s16 = t0 ^ t1 ^ s2 ^ t2 ^ t3 ^ F
//
// F = w during initialization
// F = 0 during keystream generation

wire [31:0] feedback_base;
wire [31:0] feedback_init;

assign feedback_base =
    {s[0][23:0],8'b0}
    ^ mulalpha_data
    ^ s[2]
    ^ {8'b0,s[11][31:8]}
    ^ divalpha_data;

assign feedback_init =
    feedback_base ^ w;

// =========================================================
// Keystream
// =========================================================

// Python:
// zt = s[0] ^ w

wire [31:0] zt;

assign zt = s[0] ^ w;

// =========================================================
// Handshake
// =========================================================
wire init_fire;
assign init_fire = i_init && o_init_ready;
assign o_init_ready =
    (state == ST_IDLE) ||
    ((state == ST_GEN) && !stream_valid_reg);

assign o_core_ready =
    (state == ST_GEN);

assign o_busy =
    (state != ST_IDLE);

wire output_slot_available;

assign o_stream_req_ready =
    (state == ST_GEN) &&
    (!stream_valid_reg || i_stream_ready) &&
    !init_fire;

wire stream_accept;

assign stream_accept =
    i_stream_req &&
    o_stream_req_ready;

// =========================================================
// State Update Task
// =========================================================

// LFSR and FSM update happen together.
// The combinational logic uses the old state.

integer i;

always @(posedge clk or negedge rst_n) begin

    if (!rst_n) begin

        state <= ST_IDLE;

        init_cnt <= 6'd0;

        for (i = 0; i < 16; i = i + 1)
            s[i] <= 32'd0;

        r1 <= 32'd0;
        r2 <= 32'd0;
        r3 <= 32'd0;

        stream_reg <= 32'd0;
        stream_valid_reg <= 1'b0;

    end
    else if (init_fire) begin

        /*
         * 重新加载 Key/IV
         *
         * 这里必须使用原 snow3g_core.v 中
         * 已经验证的 Key/IV 映射。
         */

        state <= ST_INIT;

        init_cnt <= 6'd0;

        r1 <= 32'b0;
        r2 <= 32'b0;
        r3 <= 32'b0;

        stream_valid_reg <= 1'b0;

        // s[0:15] <= Key/IV 初始化值
        s[15] <= k3 ^ iv0;               
        s[14] <= k2;                     
        s[13] <= k1;                     
        s[12] <= k0 ^ iv1;               
        s[11] <= k3 ^ 32'hFFFFFFFF;      
        s[10] <= k2 ^ 32'hFFFFFFFF ^ iv2;
        s[9]  <= k1 ^ 32'hFFFFFFFF ^ iv3;
        s[8]  <= k0 ^ 32'hFFFFFFFF;      
        s[7] <= k3;                      
        s[6] <= k2;                      
        s[5] <= k1;                      
        s[4] <= k0;                      
        s[3] <= k3 ^ 32'hFFFFFFFF;       
        s[2] <= k2 ^ 32'hFFFFFFFF;       
        s[1] <= k1 ^ 32'hFFFFFFFF;       
        s[0] <= k0 ^ 32'hFFFFFFFF;       
    end
    else begin

        // -------------------------------------------------
        // Output handshake
        // -------------------------------------------------

        if (stream_valid_reg && i_stream_ready)
            stream_valid_reg <= 1'b0;

        case (state)

            // =============================================
            // IDLE
            // =============================================

            ST_IDLE: begin

                if (i_init && o_init_ready) begin

                    // Python init_parameters()

                    s[15] <= k3 ^ iv0;
                    s[14] <= k2;
                    s[13] <= k1;
                    s[12] <= k0 ^ iv1;

                    s[11] <= k3 ^ 32'hFFFFFFFF;
                    s[10] <= k2 ^ 32'hFFFFFFFF ^ iv2;
                    s[9]  <= k1 ^ 32'hFFFFFFFF ^ iv3;
                    s[8]  <= k0 ^ 32'hFFFFFFFF;

                    s[7] <= k3;
                    s[6] <= k2;
                    s[5] <= k1;
                    s[4] <= k0;

                    s[3] <= k3 ^ 32'hFFFFFFFF;
                    s[2] <= k2 ^ 32'hFFFFFFFF;
                    s[1] <= k1 ^ 32'hFFFFFFFF;
                    s[0] <= k0 ^ 32'hFFFFFFFF;

                    r1 <= 32'd0;
                    r2 <= 32'd0;
                    r3 <= 32'd0;

                    init_cnt <= 6'd0;

                    stream_valid_reg <= 1'b0;

                    state <= ST_INIT;

                end

            end

            // =============================================
            // INITIALIZATION: 32 ITERATIONS
            // =============================================

            ST_INIT: begin

                // FSM update
                r1 <= new_r1;
                r2 <= new_r2;
                r3 <= new_r3;

                // LFSR shift
                for (i = 0; i < 15; i = i + 1)
                    s[i] <= s[i+1];

                s[15] <= feedback_init;

                if (init_cnt == 6'd31) begin

                    init_cnt <= 6'd0;

                    state <= ST_DISCARD;

                end
                else begin

                    init_cnt <= init_cnt + 1'b1;

                end

            end

            // =============================================
            // DISCARD FIRST WORD
            // =============================================

            ST_DISCARD: begin

                r1 <= new_r1;
                r2 <= new_r2;
                r3 <= new_r3;

                for (i = 0; i < 15; i = i + 1)
                    s[i] <= s[i+1];

                s[15] <= feedback_base;

                state <= ST_GEN;

            end

            // =============================================
            // GENERATE KEYSTREAM
            // =============================================

            ST_GEN: begin

                if (stream_accept) begin

                    stream_reg <= zt;

                    stream_valid_reg <= 1'b1;

                    // FSM update
                    r1 <= new_r1;
                    r2 <= new_r2;
                    r3 <= new_r3;

                    // LFSR update
                    for (i = 0; i < 15; i = i + 1)
                        s[i] <= s[i+1];

                    s[15] <= feedback_base;

                end

            end

            default: begin

                state <= ST_IDLE;

            end

        endcase

    end

end

endmodule