`timescale 1ns/1ps
module tb_lanes #(parameter integer TEST_AES_LOW_AREA=1);
    localparam integer AES_CYCLES = (TEST_AES_LOW_AREA==1) ? 50 : 5;
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg cstart=0,ivalid=0,oready=0,istart=0,mvalid=0;
    reg [1:0] calg=0,ialg=0;
    wire iready,ovalid,cdone,mready,mdone;
    wire [31:0] odata,mac;
    wire [15:0] obytes;
    localparam [127:0] KEY=128'hd3c5d592327fb11c4035c6680af8c6d1;
    mdm_cipher #(.AES_LOW_AREA(TEST_AES_LOW_AREA)) c(.clk(clk),.rst_n(rst_n),.start(cstart),.alg(calg),.key(KEY),
      .count(32'h398a59b4),.bearer(5'h15),.direction(1'b1),.length(16'd64),
      .in_valid(ivalid),.in_ready(iready),.in_data(32'b0),
      .out_valid(ovalid),.out_ready(oready),.out_data(odata),.out_bytes(obytes),.done(cdone));
    mdm_integrity #(.AES_LOW_AREA(TEST_AES_LOW_AREA)) m(.clk(clk),.rst_n(rst_n),.start(istart),.alg(ialg),.key(KEY),
      .count(32'h398a59b4),.bearer(5'h15),.direction(1'b1),.length(16'd64),
      .in_valid(mvalid),.in_ready(mready),.in_data(32'b0),.mac(mac),.done(mdone));

    reg [31:0] expected [1:3][0:15];
    reg [31:0] expected_mac [1:3];
    integer cycle=0,aes_n=0,aes_cycle[0:10];
    always @(posedge clk) begin
      cycle=cycle+1;
      if (rst_n && c.aes_start) begin aes_cycle[aes_n]=cycle;
          aes_n=aes_n+1;
      end
    end

    task automatic cipher_test(input integer alg, input bit stall);
      integer n,steps,first_cycle,last_cycle;
      reg [31:0] held;
      begin
        @(negedge clk);
        aes_n=0;
        calg=2'(alg);
        cstart=1;
        ivalid=0;
        oready=0;
        @(posedge clk);
        @(negedge clk);
        cstart=0;
        ivalid=1;
        if (stall) begin
          while(!ovalid) @(negedge clk);
          held=odata;
          repeat(20) begin
            @(negedge clk);
            if(!ovalid || odata!==held || iready) $fatal(1,"cipher %0d lost/stalled output",alg);
          end
        end
        n=0;
        steps=0;
        first_cycle=-1;
        last_cycle=-1;
        while(n<16) begin
          oready=stall ? ((steps%9)>=4) : 1'b1;
          @(posedge clk);
          if(ovalid && oready) begin
            if(odata!==expected[alg][n] || obytes!=4 || !iready)
              $fatal(1,"cipher alg %0d beat %0d got %h expected %h",alg,n,odata,expected[alg][n]);
            if(first_cycle<0) first_cycle=cycle;
            if(!stall && alg!=2 && last_cycle>=0 && cycle-last_cycle!=1)
              $fatal(1,"stream cipher alg %0d did not sustain one word per clock",alg);
            last_cycle=cycle;
            n=n+1;
          end else if (!stall && alg!=2 && first_cycle>=0)
            $fatal(1,"stream cipher alg %0d introduced a gap",alg);
          #1;
          if(n==16 && !cdone) $fatal(1,"cipher done missing");
          @(negedge clk);
          steps=steps+1;
          if(steps>1000) $fatal(1,"cipher lane timed out");
        end
        ivalid=0;
        oready=0;
        if(alg==2 && !stall) begin
          if(aes_n!=4) $fatal(1,"AES lane issued %0d blocks",aes_n);
          for(integer k=1;
              k<4;
              k=k+1)
            if(aes_cycle[k]-aes_cycle[k-1]!=AES_CYCLES)
              $fatal(1,"AES lane block interval was not %0d clocks",AES_CYCLES);
        end
      end
    endtask

    task automatic integrity_test(input integer alg);
      integer n,steps,last_cycle;
      begin
        @(negedge clk);
        ialg=2'(alg);
        istart=1;
        mvalid=0;
        @(posedge clk);
        @(negedge clk);
        istart=0;
        mvalid=1;
        n=0;
        steps=0;
        last_cycle=-1;
        while(n<16) begin
          @(posedge clk);
          if(mready && mvalid) begin
            if(alg!=2 && last_cycle>=0 && cycle-last_cycle!=1)
              $fatal(1,"integrity alg %0d did not sustain one word per clock",alg);
            last_cycle=cycle;
            n=n+1;
          end else if(alg!=2 && n>0) $fatal(1,"integrity alg %0d introduced a gap",alg);
          @(negedge clk);
          steps=steps+1;
          if(steps>1000) $fatal(1,"integrity lane timed out");
        end
        mvalid=0;
        steps=0;
        // EIA3 completes on the last data edge; EIA1/2 complete later.
        while(!mdone) begin @(negedge clk);
            steps=steps+1;
          if(steps>1000) $fatal(1,"MAC timed out"); end
        if(mac!==expected_mac[alg]) $fatal(1,"MAC alg %0d got %h expected %h",alg,mac,expected_mac[alg]);
      end
    endtask

    initial begin
      expected[1][0]=32'hc54058f7;
      expected[1][1]=32'ha71f0d96;
      expected[1][2]=32'h54246457;
      expected[1][3]=32'hc3b7aefd;
      expected[1][4]=32'hcb259e96;
      expected[1][5]=32'hc5f024a9;
      expected[1][6]=32'h17576d3a;
      expected[1][7]=32'h9f27028c;
      expected[1][8]=32'hec592690;
      expected[1][9]=32'hfef34d9f;
      expected[1][10]=32'h37f37355;
      expected[1][11]=32'hb5aefd74;
      expected[1][12]=32'h01ba4aa0;
      expected[1][13]=32'hf73a05ca;
      expected[1][14]=32'hd1faef71;
      expected[1][15]=32'h37d69c68;
      expected[2][0]=32'h71e57e24;
      expected[2][1]=32'h710ea81e;
      expected[2][2]=32'h6398b52b;
      expected[2][3]=32'hda5f3f94;
      expected[2][4]=32'h3eede9f6;
      expected[2][5]=32'h11328620;
      expected[2][6]=32'h231f3f1b;
      expected[2][7]=32'h328b3f88;
      expected[2][8]=32'h2b7f8905;
      expected[2][9]=32'h012f5ecc;
      expected[2][10]=32'h48fe0c87;
      expected[2][11]=32'h402256ec;
      expected[2][12]=32'h4557b418;
      expected[2][13]=32'hce7e4ed4;
      expected[2][14]=32'h38dfda29;
      expected[2][15]=32'hd1b6d8f3;
      expected[3][0]=32'h67f51c27;
      expected[3][1]=32'ha749ab41;
      expected[3][2]=32'h811084e5;
      expected[3][3]=32'hed348bdd;
      expected[3][4]=32'h2b93d00e;
      expected[3][5]=32'h33ffe690;
      expected[3][6]=32'h803afced;
      expected[3][7]=32'h61875fd4;
      expected[3][8]=32'hca49d39b;
      expected[3][9]=32'hf6ef0a98;
      expected[3][10]=32'hf510d83c;
      expected[3][11]=32'h56dceebc;
      expected[3][12]=32'h51d1b00d;
      expected[3][13]=32'hbd90081b;
      expected[3][14]=32'ha562100b;
      expected[3][15]=32'hf0caf774;
      expected_mac[1]=32'h0bcf371a;
      expected_mac[2]=32'h05a8062d;
      expected_mac[3]=32'h55f99355;
      repeat(3) @(negedge clk);
      rst_n=1;
      for(integer a=1;
          a<=3;
          a=a+1) begin cipher_test(a,0);
          cipher_test(a,1);
          integrity_test(a);
      end
      $display("PASS lane throughput, %0d-cycle AES block interval, and backpressure",AES_CYCLES);
      $finish;
    end
    initial begin #1000000;
        $fatal(1,"lane timeout");
    end
endmodule
