module aes_cmac_top (
    input  wire         clk,
    input  wire         rst_n,

    // =====================================================
    // Key Interface
    // =====================================================
    input  wire         i_key_load,
    output wire         o_key_load_ready,
    input  wire [127:0] i_int_key,
    output wire         o_key_ready,

    // =====================================================
    // MAC Start (3GPP EIA2 Parameters)
    // =====================================================
    input  wire         i_mac_start,
    output wire         o_mac_start_ready,

    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    // =====================================================
    // Message Input
    // =====================================================
    input  wire [127:0] i_data,
    input  wire         i_data_vld,
    output wire         o_data_ready,
    input  wire         i_data_last,
    input  wire [4:0]   i_valid_bytes,

    // =====================================================
    // MAC Output
    // =====================================================
    output wire [31:0]  o_mac,
    output wire         o_mac_vld,
    input  wire         i_mac_ready
);

    //----------------------------------------------------------------
    // 1. FSM Definitions & Internal Registers
    //----------------------------------------------------------------
    localparam ST_IDLE      = 3'd0;
    localparam ST_WAIT_L    = 3'd1;
    localparam ST_PROCESS   = 3'd2;
    localparam ST_WAIT_AES  = 3'd3;
    localparam ST_DONE      = 3'd4;

    reg [2:0]   current_state;
    reg [2:0]   next_state;

    reg [63:0]  leftover;       // Holds EIA2 header or lower 64-bits of previous payload
    reg [127:0] mac_state;      // Accumulated CBC state
    reg [127:0] k1, k2;         // CMAC Subkeys
    
    reg [63:0]  extra_data;     // Overflow data
    reg [7:0]   extra_V;
    reg         is_last_block;
    reg         is_extra_block;

    reg [31:0]  r_mac;
    reg         r_mac_vld;

    assign o_mac     = r_mac;
    assign o_mac_vld = r_mac_vld;

    // AES Core Interface
    reg         aes_block_vld;
    reg [127:0] aes_block_in;
    wire [127:0] aes_block_out;
    wire        aes_block_vld_out;
    wire        aes_ready;
    wire        aes_busy;

    //----------------------------------------------------------------
    // 2. Combinational Data & Padding Logic
    //----------------------------------------------------------------
    function [127:0] pad_block;
        input [127:0] block;
        input [7:0]   vbits;
        reg   [127:0] mask;
        reg   [127:0] pad;
        begin
            mask = (vbits == 0) ? 128'b0 : ~(128'hFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF >> vbits);
            pad  = (vbits == 0) ? 128'h80000000000000000000000000000000 : (128'h80000000000000000000000000000000 >> vbits);
            pad_block = (block & mask) | pad;
        end
    endfunction

    wire [7:0]   V = {3'b000, i_valid_bytes} << 3; 
    wire [7:0]   val_bits = 8'd64 + V;                   
    wire [127:0] assembled_block = {leftover, i_data[127:64]};

    // Subkey instantaneous generation
    wire [127:0] k1_next = aes_block_out[127] ? ((aes_block_out << 1) ^ 128'h00000000000000000000000000000087) : (aes_block_out << 1);
    wire [127:0] k2_next = k1_next[127]       ? ((k1_next << 1) ^ 128'h00000000000000000000000000000087)       : (k1_next << 1);

    // Handshake wiring
    assign o_mac_start_ready = (current_state == ST_IDLE) && o_key_ready && aes_ready;
    
    // BACK-TO-BACK READY: Accept data in PROCESS, or EXACTLY on the cycle AES finishes in WAIT_AES!
    wire ready_in_process  = (current_state == ST_PROCESS);
    wire ready_in_wait_aes = (current_state == ST_WAIT_AES) && aes_block_vld_out && !is_last_block && !is_extra_block;
    assign o_data_ready    = (ready_in_process || ready_in_wait_aes) && aes_ready && !aes_block_vld;

    wire data_handshake    = i_data_vld && o_data_ready;

    // Use current AES output instantly if back-to-back, else use latched mac_state
    wire [127:0] active_mac_state = (current_state == ST_WAIT_AES) ? aes_block_out : mac_state;

    //----------------------------------------------------------------
    // 3. Segment 1: FSM State Register
    //----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) current_state <= ST_IDLE;
        else        current_state <= next_state;
    end

    //----------------------------------------------------------------
    // 4. Segment 2: Next State Logic (Combinational)
    //----------------------------------------------------------------
    always @(*) begin
        next_state = current_state; // Default: hold state
        case (current_state)
            ST_IDLE: begin
                if (i_mac_start && o_mac_start_ready) next_state = ST_WAIT_L;
            end
            ST_WAIT_L: begin
                if (aes_block_vld_out) next_state = ST_PROCESS;
            end
            ST_PROCESS: begin
                if (data_handshake) next_state = ST_WAIT_AES;
            end
            ST_WAIT_AES: begin
                if (aes_block_vld_out) begin
                    if (is_last_block) 
                        next_state = ST_DONE;
                    else if (is_extra_block) 
                        next_state = ST_WAIT_AES; // Loop immediately
                    else if (data_handshake) 
                        next_state = ST_WAIT_AES; // 0-Bubble back-to-back transfer!
                    else 
                        next_state = ST_PROCESS;  // No data ready, wait in PROCESS
                end
            end
            ST_DONE: begin
                if (i_mac_ready) next_state = ST_IDLE;
            end
            default: next_state = ST_IDLE;
        endcase
    end

    //----------------------------------------------------------------
    // 5. Segment 3: Datapath & Output Logic (Sequential)
    //----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            leftover       <= 64'b0;
            mac_state      <= 128'b0;
            k1             <= 128'b0;
            k2             <= 128'b0;
            extra_data     <= 64'b0;
            extra_V        <= 8'b0;
            is_last_block  <= 1'b0;
            is_extra_block <= 1'b0;
            r_mac          <= 32'b0;
            r_mac_vld      <= 1'b0;
            aes_block_vld  <= 1'b0;
            aes_block_in   <= 128'b0;
        end else begin
            aes_block_vld <= 1'b0; // Default pulse

            // Always update MAC state when AES finishes a block
            if (aes_block_vld_out) begin
                mac_state <= aes_block_out;
            end

            case (current_state)
                ST_IDLE: begin
                    if (i_mac_start && o_mac_start_ready) begin
                        leftover      <= {i_count, i_bearer, i_direction, 26'b0};
                        mac_state     <= 128'b0;
                        aes_block_in  <= 128'b0; // Generate L = AES(0^128)
                        aes_block_vld <= 1'b1;
                    end
                end

                ST_WAIT_L: begin
                    if (aes_block_vld_out) begin
                        k1 <= k1_next;
                        k2 <= k2_next;
                    end
                end

                ST_PROCESS, ST_WAIT_AES: begin
                    // Priority 1: Launch extra padded block immediately
                    if (current_state == ST_WAIT_AES && aes_block_vld_out && is_extra_block) begin
                        aes_block_in   <= pad_block({extra_data, 64'b0}, extra_V) ^ aes_block_out ^ k2;
                        aes_block_vld  <= 1'b1;
                        is_last_block  <= 1'b1;
                        is_extra_block <= 1'b0;
                    end
                    // Priority 2: MAC calculation complete
                    else if (current_state == ST_WAIT_AES && aes_block_vld_out && is_last_block) begin
                        r_mac     <= aes_block_out[127:96];
                        r_mac_vld <= 1'b1;
                    end
                    // Priority 3: Process incoming data (Applies to both PROCESS and WAIT_AES zero-bubble)
                    else if (data_handshake) begin
                        leftover <= i_data[63:0];

                        if (!i_data_last) begin
                            aes_block_in   <= assembled_block ^ active_mac_state;
                            is_last_block  <= 1'b0;
                            is_extra_block <= 1'b0;
                            aes_block_vld  <= 1'b1;
                        end else begin
                            if (V == 8'd64) begin
                                aes_block_in   <= assembled_block ^ active_mac_state ^ k1;
                                is_last_block  <= 1'b1;
                                is_extra_block <= 1'b0;
                                aes_block_vld  <= 1'b1;
                            end else if (V < 8'd64) begin
                                aes_block_in   <= pad_block(assembled_block, val_bits) ^ active_mac_state ^ k2;
                                is_last_block  <= 1'b1;
                                is_extra_block <= 1'b0;
                                aes_block_vld  <= 1'b1;
                            end else begin
                                aes_block_in   <= assembled_block ^ active_mac_state;
                                extra_data     <= i_data[63:0];
                                extra_V        <= V - 8'd64;
                                is_last_block  <= 1'b0;
                                is_extra_block <= 1'b1;
                                aes_block_vld  <= 1'b1;
                            end
                        end
                    end
                end

                ST_DONE: begin
                    if (i_mac_ready) r_mac_vld <= 1'b0;
                end
            endcase
        end
    end

    //----------------------------------------------------------------
    // 6. Dedicated AES Core Instantiation
    //----------------------------------------------------------------
    aes_core_5cycle u_aes_core_mac (
        .clk              (clk),
        .rst_n            (rst_n),
        .i_key_load       (i_key_load),
        .o_key_load_ready (o_key_load_ready),
        .i_key            (i_int_key),
        .o_key_ready      (o_key_ready),
        .i_block_vld      (aes_block_vld),
        .o_block_ready    (aes_ready),
        .i_block          (aes_block_in),
        .o_block          (aes_block_out),
        .o_block_vld      (aes_block_vld_out),
        .i_block_ready    (1'b1),
        .o_finish_data    (),
        .o_finish_valid   (),
        .o_busy           (aes_busy)
    );

endmodule