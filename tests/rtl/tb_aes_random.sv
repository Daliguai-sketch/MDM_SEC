`timescale 1ns/1ps
// Check changing keys/inputs, ignored busy requests, exact latency,
// final-edge reissue, idle gaps and reset at several points in a block.
module tb_aes_random #(parameter integer TEST_AES_LOW_AREA=1);
    localparam integer CYCLES = (TEST_AES_LOW_AREA==1) ? 50 : 5;
    localparam integer MAX_VECTORS = 1024;
    reg clk=0,rst_n=0,start=0;
    always #5 clk=~clk;
    reg [127:0] key=0,block_in=0;
    wire ready,busy,done;
    wire [127:0] block_out;
    mdm_aes128 #(.AES_LOW_AREA(TEST_AES_LOW_AREA)) dut(
        .clk(clk),.rst_n(rst_n),.start(start),.ready(ready),
        .key(key),.block_in(block_in),.busy(busy),.done(done),.block_out(block_out)
    );

    reg [127:0] keys[0:MAX_VECTORS-1];
    reg [127:0] blocks[0:MAX_VECTORS-1];
    reg [127:0] expected[0:MAX_VECTORS-1];
    integer launch_cycle[0:MAX_VECTORS-1];
    integer fd,rc,count=0,cycle=0,sent=0,completed=0,back_to_back=0;
    integer vector_limit;
    reg scoreboard_active=0;
    string vector_path,wave_path;
    initial begin
        if ($value$plusargs("WAVE=%s",wave_path)) begin
            $display("Writing AES waveform: %s",wave_path);
            $dumpfile(wave_path);
            $dumpvars(0,tb_aes_random);
        end
    end
`ifdef MDM_SEC_FSDB
    string fsdb_path;
    initial begin
        if ($value$plusargs("FSDB=%s",fsdb_path)) begin
            $display("Writing AES FSDB: %s",fsdb_path);
            $fsdbDumpfile(fsdb_path);
            $fsdbDumpvars(0,tb_aes_random);
        end
    end
`endif

    always @(posedge clk) begin
        if (rst_n && scoreboard_active) begin
            cycle=cycle+1;
            if (start && ready) begin
                if (sent>=count) $fatal(1,"unexpected AES acceptance");
                launch_cycle[sent]=cycle;
                if (sent>0 && cycle-launch_cycle[sent-1]==CYCLES)
                    back_to_back=back_to_back+1;
                if($test$plusargs("CASE_LOG"))
                    $display("AES start block=%0d cycle=%0d input=%032h key=%032h at %0t",
                             sent,cycle,block_in,key,$time);
                sent=sent+1;
            end
            #1;
            if (done) begin
                if (completed>=sent || cycle-launch_cycle[completed]!=CYCLES)
                    $fatal(1,"AES completion at wrong cycle, block %0d",completed);
                if (block_out!==expected[completed])
                    $fatal(1,"AES block %0d: got %h expected %h",completed,block_out,expected[completed]);
                if($test$plusargs("CASE_LOG"))
                    $display("AES done block=%0d cycle=%0d output=%032h at %0t",
                             completed,cycle,block_out,$time);
                completed=completed+1;
            end else if (completed<sent && cycle-launch_cycle[completed]>=CYCLES) begin
                $fatal(1,"AES completion missing for block %0d",completed);
            end
        end
    end

    task automatic abort_block(input integer elapsed);
        begin
            @(negedge clk);
            if (!ready || busy) $fatal(1,"AES not idle before reset setup");
            key=keys[0];
            block_in=blocks[0];
            start=1;
            @(posedge clk);
            #1;
            if (!busy || done) $fatal(1,"AES did not start reset setup");
            @(negedge clk);
            start=0;
            repeat(elapsed) begin
                @(posedge clk);
                #1;
                if(done) $fatal(1,"AES completed before reset setup");
            end
            @(negedge clk);
            rst_n=0;
            #1;
            if(busy || done || block_out!==0)
                $fatal(1,"AES reset did not abort and clear outputs");
            @(negedge clk);
            rst_n=1;
            repeat(CYCLES+2) begin
                @(posedge clk);
                #1;
                if(done || busy || !ready) $fatal(1,"aborted AES block reappeared");
            end
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s",vector_path))
            $fatal(1,"pass +VECTORS=path");
        fd=$fopen(vector_path,"r");
        if(fd==0) $fatal(1,"cannot open AES vectors");
        rc=$fscanf(fd,"%h %h %h\n",keys[count],blocks[count],expected[count]);
        while(rc==3) begin
            count=count+1;
            if(count>=MAX_VECTORS) $fatal(1,"too many AES vectors");
            rc=$fscanf(fd,"%h %h %h\n",keys[count],blocks[count],expected[count]);
        end
        if(rc!=-1 || count<200) $fatal(1,"bad or insufficient AES vectors");
        $fclose(fd);
        // A smaller prefix keeps an interactive waveform compact. The default
        // regression still checks all vectors and its 200-block coverage.
        if ($value$plusargs("LIMIT=%d",vector_limit)) begin
            if(vector_limit<2 || vector_limit>count) $fatal(1,"invalid AES vector LIMIT");
            count=vector_limit;
        end
        repeat(3) @(negedge clk);
        rst_n=1;
        abort_block(0);
        abort_block(1);
        abort_block(CYCLES/2);
        abort_block(CYCLES-1);
        @(negedge clk);
        scoreboard_active=1;
        while(completed<count) begin
            @(negedge clk);
            start=0;
            if(sent<count) begin
                if(ready) begin
                    // First 200 blocks are reissued at every earliest edge;
                    // afterwards deliberately insert some idle gaps.
                    if(sent<200 || cycle%7!=0) begin
                        key=keys[sent];
                        block_in=blocks[sent];
                        start=1;
                    end
                end else begin
                    // Input noise and illegal busy pulses must be ignored.
                    key=~keys[sent];
                    block_in=~blocks[sent];
                    start=(cycle%3==0);
                end
            end
        end
        start=0;
        if(back_to_back<((count<200) ? count-1 : 199))
            $fatal(1,"AES earliest-edge coverage incomplete");
        repeat(5) begin
            @(posedge clk);
            #1;
            if(done || busy || !ready) $fatal(1,"AES did not return to idle");
        end
        $display("PASS %0d AES blocks, %0d-cycle latency/II, %0d back-to-back, busy pulses and resets",
                 count,CYCLES,back_to_back);
        $finish;
    end
    initial begin
        #10000000;
        $fatal(1,"AES random test timeout");
    end
endmodule
