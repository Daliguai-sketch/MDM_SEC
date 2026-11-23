`timescale 1ns/1ps
// Exact top-level timing example in mdm_sec_spec: mode 4, EEA0/EIA0,
// A=5 bytes, B=3 bytes. E7 and E9 are stalled response/output edges.
module tb_spec_timing;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;

    reg cmd_valid=0, in_valid=0, rsp_ready=0, cipher_ready=0;
    wire cmd_ready, in_ready, rsp_valid, rsp_mac_valid, rsp_error;
    wire cipher_valid, cipher_last, rsp_rx_mac_valid, rsp_mac_match;
    reg [2:0] cmd_mode=4;
    reg [1:0] cmd_cipher_alg=0, cmd_int_alg=0;
    reg [127:0] cmd_cipher_key=0, cmd_int_key=0;
    reg [31:0] cmd_count=0;
    reg [4:0] cmd_bearer=0;
    reg cmd_direction=0;
    reg [15:0] cmd_a_bytes=5, cmd_b_bytes=3;
    reg [127:0] in_data=0;
    wire [31:0] rsp_mac, rsp_rx_mac;
    wire [15:0] rsp_cipher_bytes, cipher_keep;
    wire [127:0] cipher_data;

    mdm_sec #(.MAX_BYTES(32), .AES_LOW_AREA(1)) dut (.*);

    integer e;
    reg [2:0] expected_state;
    initial begin
        repeat (2) @(negedge clk);
        rst_n=1;
        for (e=0;
             e<=10;
             e=e+1) begin
            // Drive inputs between edges; sample the actual handshake at the
            // following rising edge before observing registered updates.
            @(negedge clk);
            cmd_valid=(e==0);
            in_valid=(e==1 || e==2);
            if (e==1) in_data=128'h11223344550000000000000000000000;
            if (e==2) in_data=128'h66778800000000000000000000000000;
            rsp_ready=(e==8);
            cipher_ready=(e==10);
            @(posedge clk);
            if (cmd_ready !== (e==0) || in_ready !== (e==1 || e==2))
                $fatal(1,"command/input ready mismatch at E%0d",e);
            if (dut.enc_start !== (e==3) || dut.int_start !== (e==3))
                $fatal(1,"lane starts mismatch at E%0d",e);
            if (dut.int_done !== (e==4) || dut.enc_done !== (e==5))
                $fatal(1,"lane done mismatch at E%0d",e);
            if (rsp_valid !== (e==7 || e==8) || cipher_valid !== (e==9 || e==10))
                $fatal(1,"response/output valid mismatch at E%0d",e);
            #1;
            case (e)
                0: expected_state=1;             // LOAD_A
                1: expected_state=2;             // LOAD_B
                2,3,4,5: expected_state=3;     // RUN
                6,7: expected_state=4;         // RESPONSE
                8,9: expected_state=5;         // OUTPUT
                10: expected_state=0;          // IDLE
                default: expected_state=0;
            endcase
            if (dut.state !== expected_state)
                $fatal(1,"post-edge state mismatch at E%0d",e);
            if (e==6 || e==7) begin
                if (!rsp_valid || rsp_error || !rsp_mac_valid || rsp_mac!==0 ||
                    rsp_cipher_bytes!==3 || rsp_rx_mac_valid)
                    $fatal(1,"response changed or incorrect at E%0d",e);
            end
            if (e==8 || e==9) begin
                if (!cipher_valid || cipher_data!==128'h66778800000000000000000000000000 ||
                    cipher_keep!==16'he000 || !cipher_last)
                    $fatal(1,"cipher output changed or incorrect at E%0d",e);
            end
        end
        if (!cmd_ready || cipher_valid || rsp_valid)
            $fatal(1,"did not return to idle after output handshake");
        $display("PASS documented MDM_SEC E0..E10 timing, handshakes and stalls");
        $finish;
    end

    initial begin
        #10000;
        $fatal(1,"spec timing test timeout");
    end
endmodule
