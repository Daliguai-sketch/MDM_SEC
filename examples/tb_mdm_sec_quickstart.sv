`timescale 1ns/1ps
// Simulation example only: mode 4, AES-CTR plus AES-CMAC.
// The fixed keys and protocol parameters are for demonstration, not deployment.
module tb_mdm_sec_quickstart;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0;
    reg cmd_valid=0;
    wire cmd_ready;
    reg in_valid=0;
    wire in_ready;
    reg [127:0] in_data=0;
    reg rsp_ready=0;
    wire rsp_valid;
    wire [31:0] rsp_mac;
    wire rsp_mac_valid;
    wire [15:0] rsp_cipher_bytes;
    wire rsp_error;
    wire [31:0] rsp_rx_mac;
    wire rsp_rx_mac_valid,rsp_mac_match;
    reg cipher_ready=0;
    wire cipher_valid,cipher_last;
    wire [127:0] cipher_data;
    wire [15:0] cipher_keep;

    mdm_sec #(.MAX_BYTES(2048)) dut (
        .clk(clk), .rst_n(rst_n),
        .cmd_valid(cmd_valid), .cmd_ready(cmd_ready),
        .cmd_mode(3'd4), .cmd_cipher_alg(2'd2), .cmd_int_alg(2'd2),
        .cmd_cipher_key(128'h000102030405060708090a0b0c0d0e0f),
        .cmd_int_key(128'h0f0e0d0c0b0a09080706050403020100),
        .cmd_count(32'h398a59b4), .cmd_bearer(5'h15), .cmd_direction(1'b1),
        .cmd_a_bytes(16'd5), .cmd_b_bytes(16'd3),
        .in_valid(in_valid), .in_ready(in_ready), .in_data(in_data),
        .rsp_valid(rsp_valid), .rsp_ready(rsp_ready),
        .rsp_mac(rsp_mac), .rsp_mac_valid(rsp_mac_valid),
        .rsp_cipher_bytes(rsp_cipher_bytes), .rsp_error(rsp_error),
        .cipher_valid(cipher_valid), .cipher_ready(cipher_ready),
        .cipher_data(cipher_data), .cipher_keep(cipher_keep), .cipher_last(cipher_last),
        .rsp_rx_mac(rsp_rx_mac), .rsp_rx_mac_valid(rsp_rx_mac_valid),
        .rsp_mac_match(rsp_mac_match)
    );

    // Drive on a falling edge, then hold valid/data until a rising-edge handshake.
    task automatic send_input(input [127:0] word);
        begin
            @(negedge clk);
            in_data=word;
            in_valid=1;
            @(posedge clk);
            while(!in_ready) @(posedge clk);
            @(negedge clk);
            in_valid=0;
        end
    endtask

    initial begin
        repeat(3) @(negedge clk);
        rst_n=1;
        @(negedge clk);
        cmd_valid=1;
        @(posedge clk);
        while(!cmd_ready) @(posedge clk);
        @(negedge clk);
        cmd_valid=0;

        // Each segment starts on a new beat; high-order bytes are valid.
        send_input(128'h11223344550000000000000000000000);
        send_input(128'h66778800000000000000000000000000);

        // The response is consumed before the cipher output becomes available.
        @(negedge clk);
        rsp_ready=1;
        @(posedge clk);
        while(!rsp_valid) @(posedge clk);
        if(rsp_error || !rsp_mac_valid || rsp_mac!==32'hf387a200 ||
           rsp_cipher_bytes!==16'd3 || rsp_rx_mac_valid || rsp_mac_match)
            $fatal(1,"unexpected response: error=%b mac=%h mac_valid=%b bytes=%0d",
                   rsp_error,rsp_mac,rsp_mac_valid,rsp_cipher_bytes);
        $display("Response: MAC=%08h, cipher_bytes=%0d",rsp_mac,rsp_cipher_bytes);
        @(negedge clk);
        rsp_ready=0;
        cipher_ready=1;
        @(posedge clk);
        while(!cipher_valid) @(posedge clk);
        if(cipher_data!==128'h73830000000000000000000000000000 ||
           cipher_keep!==16'he000 || !cipher_last)
            $fatal(1,"unexpected output: data=%h keep=%h last=%b",cipher_data,cipher_keep,cipher_last);
        $display("Cipher:   data=%032h, keep=%04h, last=%b",cipher_data,cipher_keep,cipher_last);
        @(negedge clk);
        cipher_ready=0;
        if(!cmd_ready) $fatal(1,"not ready for the next command");
        $display("PASS mode 4 AES-CTR/AES-CMAC quickstart");
        $finish;
    end

    initial begin
        #100000;
        $fatal(1,"quickstart timed out");
    end
endmodule
