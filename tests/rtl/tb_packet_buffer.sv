`timescale 1ns/1ps
module tb_packet_buffer #(
    parameter integer TEST_CAP=259,
    parameter integer TEST_READ_PORTS=2
);
    localparam integer CAP=TEST_CAP;
    reg clk=0;
    always #5 clk=~clk;
    reg wr_en=0;
    reg [15:0] wr_addr=0,rd0_addr=0,rd1_addr=0;
    reg [15:0] wr_bytes=0;
    reg [127:0] wr_data=0;
    wire [127:0] rd0_data;
    wire [31:0] rd1_data;
    mdm_packet_buffer #(.CAP_BYTES(CAP),.READ_PORTS(TEST_READ_PORTS)) dut(.*);
    reg [7:0] expected[0:CAP-1];
    integer pos,n,step,k,r0,r1;
    reg [127:0] data_word;
    initial begin
        for(pos=0;
            pos<CAP;
            pos=pos+16) begin
            n=(CAP-pos>=16) ? 16 : CAP-pos;
            data_word=0;
            for(k=0;
                k<n;
                k=k+1) begin
                expected[pos+k]=8'((pos+k)*37+19);
                data_word[127-8*k -: 8]=expected[pos+k];
            end
            @(negedge clk);
            wr_en=1;
            wr_addr=16'(pos);
            wr_bytes=16'(n);
            wr_data=data_word;
            @(posedge clk);
        end
        // Unaligned writes of 1..16 bytes and independent 128/32-bit reads,
        // including partial accesses at the end of the odd-sized buffer.
        for(step=0;
            step<1000;
            step=step+1) begin
            pos=(step*73+17)%CAP;
            n=1+(step%16);
            if(pos+n>CAP) n=CAP-pos;
            r0=(step*31+5)%CAP;
            r1=(step*67+249)%CAP;
            if(step%10==0) begin
                r0=pos;
                r1=pos;
            end
            for(k=0;
                k<16;
                k=k+1) data_word[127-8*k -: 8]=8'(step*31+k*73);
            @(negedge clk);
            wr_en=1;
            wr_addr=16'(pos);
            wr_bytes=16'(n);
            wr_data=data_word;
            rd0_addr=16'(r0);
            rd1_addr=16'(r1);
            @(posedge clk);
            // Both consumers sample old contents at the write edge. This is
            // essential when mode 2/4 reads original B as cipher overwrites it.
            for(k=0;
                k<16;
                k=k+1)
                if(r0+k<CAP && rd0_data[127-8*k -: 8]!==expected[r0+k])
                    $fatal(1,"pre-write read0 step=%0d addr=%0d",step,r0+k);
            for(k=0;
                k<4;
                k=k+1)
                if(TEST_READ_PORTS==2 && r1+k<CAP && rd1_data[31-8*k -: 8]!==expected[r1+k])
                    $fatal(1,"pre-write read1 step=%0d addr=%0d",step,r1+k);
            for(k=0;
                k<n;
                k=k+1) expected[pos+k]=data_word[127-8*k -: 8];
            #1;
            for(k=0;
                k<16;
                k=k+1) begin
                if(r0+k<CAP && rd0_data[127-8*k -: 8]!==expected[r0+k])
                    $fatal(1,"bank read0 step=%0d addr=%0d",step,r0+k);
            end
            for(k=0;
                k<4;
                k=k+1) begin
                if(TEST_READ_PORTS==2 && r1+k<CAP && rd1_data[31-8*k -: 8]!==expected[r1+k])
                    $fatal(1,"bank read1 step=%0d addr=%0d",step,r1+k);
            end
            if(TEST_READ_PORTS==1 && rd1_data!==0)
                $fatal(1,"disabled second read port must be zero");
        end
        // At the full 16-bit address limit, mode-2 MAC bytes may wrap from
        // 0xffff to 0x0000 after the original A has been consumed.
        if(CAP==65536) begin
            for(step=1;
                step<=15;
                step=step+1) begin
                pos=65536-step;
                n=16;
                for(k=0;
                    k<16;
                    k=k+1) data_word[127-8*k -: 8]=8'(step*13+k*71);
                @(negedge clk);
                wr_en=1;
                wr_addr=16'(pos);
                wr_bytes=16'(n);
                wr_data=data_word;
                rd0_addr=16'(pos);
                rd1_addr=16'(pos);
                @(posedge clk);
                for(k=0;
                    k<16;
                    k=k+1)
                    if(rd0_data[127-8*k -: 8]!==expected[(pos+k)%CAP])
                        $fatal(1,"pre-write wrap read0 step=%0d byte=%0d",step,k);
                for(k=0;
                    k<4;
                    k=k+1)
                    if(TEST_READ_PORTS==2 && rd1_data[31-8*k -: 8]!==expected[(pos+k)%CAP])
                        $fatal(1,"pre-write wrap read1 step=%0d byte=%0d",step,k);
                for(k=0;
                    k<n;
                    k=k+1) expected[(pos+k)%CAP]=data_word[127-8*k -: 8];
                #1;
                for(k=0;
                    k<16;
                    k=k+1)
                    if(rd0_data[127-8*k -: 8]!==expected[(pos+k)%CAP])
                        $fatal(1,"wrap read0 step=%0d byte=%0d",step,k);
                for(k=0;
                    k<4;
                    k=k+1)
                    if(TEST_READ_PORTS==2 && rd1_data[31-8*k -: 8]!==expected[(pos+k)%CAP])
                        $fatal(1,"wrap read1 step=%0d byte=%0d",step,k);
            end
        end
        @(negedge clk);
        wr_en=0;
        $display("PASS 16-bank unaligned writes/reads CAP=%0d READ_PORTS=%0d",CAP,TEST_READ_PORTS);
        $finish;
    end
    initial begin #1000000;
        $fatal(1,"buffer timeout");
    end
endmodule
