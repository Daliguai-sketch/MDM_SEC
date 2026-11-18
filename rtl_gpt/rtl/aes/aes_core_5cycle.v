module aes_core_5cycle (
    input  wire         clk,
    input  wire         rst_n,

    // Key Interface
    input  wire         i_key_load,
    output wire         o_key_load_ready,
    input  wire [127:0] i_key,
    output wire         o_key_ready,

    // Data Interface
    input  wire         i_block_vld,
    output wire         o_block_ready,
    input  wire [127:0] i_block,
    output wire [127:0] o_block,
    output wire         o_block_vld,
    input  wire         i_block_ready,

    // Status
    output wire         o_finish_data,
    output wire         o_finish_valid,
    output wire         o_busy
);

    //----------------------------------------------------------------
    // 1. Master Key Register & On-the-Fly 2-Step Expander
    //----------------------------------------------------------------
    reg [127:0] key_reg;
    reg         key_vld;
    reg [127:0] curr_key_reg; // Holds current intermediate key for next cycle

    assign o_key_load_ready = !o_busy;
    assign o_key_ready      = key_vld;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            key_reg <= 128'b0;
            key_vld <= 1'b0;
        end else if (i_key_load) begin
            key_reg <= i_key;
            key_vld <= 1'b1;
        end
    end

    // Initial rk[0] from master key_reg with MDM_SEC word swapping
    wire [127:0] rk0 = {key_reg[31:0], key_reg[63:32], key_reg[95:64], key_reg[127:96]};

    reg [2:0] round_cnt;
    reg       busy;
    wire      is_start = i_block_vld && o_block_ready;

    // Rcon Muxing for Step A & Step B based on round_cnt
    reg [31:0] rcon_a, rcon_b;
    always @(*) begin
        if (is_start) begin
            rcon_a = 32'h01000000; rcon_b = 32'h02000000; // Round 1 & 2
        end else begin
            case (round_cnt)
                3'd2: begin rcon_a = 32'h04000000; rcon_b = 32'h08000000; end // Round 3 & 4
                3'd3: begin rcon_a = 32'h10000000; rcon_b = 32'h20000000; end // Round 5 & 6
                3'd4: begin rcon_a = 32'h40000000; rcon_b = 32'h80000000; end // Round 7 & 8
                3'd5: begin rcon_a = 32'h1b000000; rcon_b = 32'h36000000; end // Round 9 & 10
                default: begin rcon_a = 32'h01000000; rcon_b = 32'h02000000; end
            endcase
        end
    end

    // Input to Step A: rk0 on start, curr_key_reg during processing
    wire [127:0] step_a_in = is_start ? rk0 : curr_key_reg;
    wire [127:0] round_key_a;
    wire [127:0] round_key_b;

    // ONLY 2 Key Expand Step instances used for the ENTIRE core!
    aes_key_expand_step u_key_step_a (.i_key(step_a_in),   .i_rcon(rcon_a), .o_next_key(round_key_a));
    aes_key_expand_step u_key_step_b (.i_key(round_key_a), .i_rcon(rcon_b), .o_next_key(round_key_b));

    //----------------------------------------------------------------
    // 2. Data Path Logic & Double Round
    //----------------------------------------------------------------
    reg [127:0] state_reg;
    reg         out_vld_reg;

    assign o_busy        = busy;
    assign o_block_ready = (!busy || (round_cnt == 3'd5)) && key_vld;

    // Round 0 AddRoundKey
    wire [127:0] current_state = is_start ? (i_block ^ rk0) : state_reg;

    wire [127:0] round_out_1;
    wire [127:0] round_out_2;
    wire         last_round_b = (!is_start && (round_cnt == 3'd5));

    aes_round_comb u_rA (
        .state_in  (current_state),
        .round_key (round_key_a),
        .last_round(1'b0),
        .state_out (round_out_1)
    );

    aes_round_comb u_rB (
        .state_in  (round_out_1),
        .round_key (round_key_b),
        .last_round(last_round_b),
        .state_out (round_out_2)
    );

    // Direct Output Mux for Round 10
    assign o_block_vld = (busy && (round_cnt == 3'd5)) || out_vld_reg;
    assign o_block     = (busy && (round_cnt == 3'd5)) ? round_out_2 : state_reg;

    //----------------------------------------------------------------
    // 3. FSM Logic
    //----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_reg    <= 128'b0;
            curr_key_reg <= 128'b0;
            round_cnt    <= 3'd0;
            busy         <= 1'b0;
            out_vld_reg  <= 1'b0;
        end else begin
            if (is_start) begin
                state_reg    <= round_out_2;
                curr_key_reg <= round_key_b; // Save rk[2] for next cycle
                round_cnt    <= 3'd2;
                busy         <= 1'b1;
                out_vld_reg  <= 1'b0;
            end else if (busy) begin
                if (round_cnt == 3'd5) begin
                    state_reg   <= round_out_2;
                    busy        <= 1'b0;
                    round_cnt   <= 3'd0;
                    out_vld_reg <= 1'b1;
                end else begin
                    state_reg    <= round_out_2;
                    curr_key_reg <= round_key_b; // Save current cycle's rk_b
                    round_cnt    <= round_cnt + 1'b1;
                end
            end else if (i_block_ready) begin
                out_vld_reg <= 1'b0;
            end
        end
    end

    assign o_finish_data  = o_block_vld;
    assign o_finish_valid = o_block_vld;

endmodule