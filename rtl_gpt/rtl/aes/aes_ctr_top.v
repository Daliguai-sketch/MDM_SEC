module aes_ctr_top (
    input  wire         clk,
    input  wire         rst_n,

    // =====================================================
    // Key Configuration
    // =====================================================
    input  wire         i_key_load,
    output wire         o_key_load_ready,

    input  wire [127:0] i_key,
    output wire         o_key_ready,

    // =====================================================
    // CTR Configuration
    // =====================================================
    input  wire         i_ctr_init,
    output wire         o_ctr_init_ready,

    input  wire [31:0]  i_count,
    input  wire [4:0]   i_bearer,
    input  wire         i_direction,

    // =====================================================
    // Stream Request
    // =====================================================
    input  wire         i_stream_vld,
    output wire         o_stream_ready,

    // =====================================================
    // Keystream Output
    // =====================================================
    output wire [127:0] o_stream,
    output wire         o_stream_vld,
    input  wire         i_stream_ready
);

    //----------------------------------------------------------------
    // 1. Internal Registers & State
    //----------------------------------------------------------------
    reg         running;
    reg [127:0] ctr_blk;      // {COUNT, BEARER, DIRECTION, 26'b0, COUNTER}
    reg [127:0] r_stream;
    reg         r_stream_vld;

    // Dedicated AES Core Interface
    reg         aes_block_vld;
    reg [127:0] aes_block_in;
    wire [127:0] aes_block_out;
    wire        aes_block_vld_out;
    wire        aes_ready;

    // Direct instantiation of 5-cycle AES Core
    aes_core_5cycle u_aes_core_ctr (
        .clk              (clk),
        .rst_n            (rst_n),
        .i_key_load       (i_key_load),
        .o_key_load_ready (o_key_load_ready),
        .i_key            (i_key),
        .o_key_ready      (o_key_ready),
        .i_block_vld      (aes_block_vld),
        .o_block_ready    (aes_ready),
        .i_block          (aes_block_in),
        .o_block          (aes_block_out),
        .o_block_vld      (aes_block_vld_out),
        .i_block_ready    (1'b1),
        .o_finish_data    (),
        .o_finish_valid   (),
        .o_busy           ()
    );

    // ZERO-LATENCY BYPASS COMBINATIONAL OUTPUT
    // Serve buffered data if present; else serve core output directly at 5th cycle
    assign o_stream_vld     = r_stream_vld | aes_block_vld_out;
    assign o_stream         = r_stream_vld ? r_stream : aes_block_out;

    assign o_ctr_init_ready = o_key_ready && aes_ready;
    assign o_stream_ready   = running && aes_ready;

    // Handshake Condition: Stream valid, requested, and ready
    wire stream_handshake   = o_stream_vld && i_stream_vld && i_stream_ready;

    //----------------------------------------------------------------
    // 2. High-Performance Control Logic (Strict 5 Cycles/Block)
    //----------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            running       <= 1'b0;
            ctr_blk       <= 128'b0;
            r_stream      <= 128'b0;
            r_stream_vld  <= 1'b0;
            aes_block_vld <= 1'b0;
            aes_block_in  <= 128'b0;
        end else begin
            aes_block_vld <= 1'b0; // Default pulse

            // 1. Initialize CTR_0
            if (i_ctr_init && o_ctr_init_ready) begin
                ctr_blk       <= {i_count, i_bearer, i_direction, 26'b0, 64'd1};
                aes_block_in  <= {i_count, i_bearer, i_direction, 26'b0, 64'd0}; // Launch CTR_0
                aes_block_vld <= 1'b1;
                running       <= 1 me0; // Protection check
                running       <= 1'b1;
                r_stream_vld  <= 1'b0;
            end 
            else if (running) begin
                // 2. Stream Block Consumed (d5 Same-Cycle 接力)
                if (stream_handshake) begin
                    r_stream_vld <= 1'b0;

                    // Immediately launch next counter block on same edge
                    aes_block_in  <= ctr_blk;
                    aes_block_vld <= 1'b1;
                    ctr_blk[63:0] <= ctr_blk[63:0] + 1'b1;
                end
                // 3. Core finished, but downstream not ready (Mode 2) -> Lock in buffer safely
                else if (aes_block_vld_out && !r_stream_vld) begin
                    r_stream     <= aes_block_out;
                    r_stream_vld <= 1'b1;
                end
            end
        end
    end

endmodule