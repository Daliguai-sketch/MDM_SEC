`timescale 1ns/1ps
module tb_mdm_sec #(parameter integer TEST_MAX_BYTES=2048);
    reg clk=0,rst_n=0;
    always #5 clk=~clk;
    reg cmd_valid=0,in_valid=0,rsp_ready=0,cipher_ready=0;
    wire cmd_ready,in_ready,rsp_valid,rsp_mac_valid,rsp_error,cipher_valid,cipher_last;
    reg [2:0] cmd_mode=0;
    reg [1:0] cmd_cipher_alg=0,cmd_int_alg=0;
    reg [127:0] cmd_cipher_key=0,cmd_int_key=0;
    reg [31:0] cmd_count=0;
    reg [127:0] in_data=0;
    reg [4:0] cmd_bearer=0;
    reg cmd_direction=0;
    reg [15:0] cmd_a_bytes=0,cmd_b_bytes=0;
    wire [31:0] rsp_mac,rsp_rx_mac;
    wire rsp_rx_mac_valid,rsp_mac_match;
    wire [127:0] cipher_data;
    wire [15:0] rsp_cipher_bytes;
    wire [15:0] cipher_keep;
    mdm_sec #(.MAX_BYTES(TEST_MAX_BYTES)) dut(.*);

    integer cycle_count=0,enc_started_at=-1,int_started_at=-1,enc_done_at=-1,int_done_at=-1;
    integer enc_start_count=0,int_start_count=0,rx_captured_at=-1,aes_issued_count=0;
    integer produced_bytes=0,overlap_cycles=0,enc_before_int_done=0,int_before_enc_done=0;
    integer wait_for_mac=0,wait_for_result=0;
    integer overlap_cases [2:5];
    integer dependency_cases [2:5];
    reg [11:0] overlap_pair_mask [2:5];
    integer check_n,check_end,check_needed;
    always @(posedge clk) begin
        cycle_count=cycle_count+1;
        if (rst_n) begin
            if (dut.enc_start) begin
                enc_started_at=cycle_count;
                enc_start_count=enc_start_count+1;
                produced_bytes=0;
                overlap_cycles=0;
                enc_before_int_done=0;
                int_before_enc_done=0;
                wait_for_mac=0;
                wait_for_result=0;
            end
            if (dut.int_start) begin
                int_started_at=cycle_count;
                int_start_count=int_start_count+1;
            end
            if (dut.enc_done) enc_done_at=cycle_count;
            if (dut.int_done) int_done_at=cycle_count;
            if (dut.capture_rx_mac) rx_captured_at=cycle_count;
            if (dut.u_cipher.aes_start) aes_issued_count=aes_issued_count+1;
            // Count actual opportunities blocked by the producer, not just
            // cycles when the consuming algorithm is still initializing.
            if(dut.mode_q==3'd2 && dut.enc_started && !dut.enc_finished &&
               dut.enc_pos<dut.enc_len && dut.enc_in_ready && !dut.enc_dep_ready)
                wait_for_mac=wait_for_mac+1;
            if((dut.mode_q==3'd3 || dut.mode_q==3'd5) && dut.int_started && !dut.int_finished &&
               dut.int_pos<dut.int_len && dut.int_in_ready && !dut.int_dep_ready)
                wait_for_result=wait_for_result+1;
            // Check against independently counted bytes written on earlier
            // edges, before counting any write from the current edge.
            if (dut.int_in_valid && dut.int_in_ready &&
                (dut.mode_q==3'd3 || dut.mode_q==3'd5)) begin
                check_n=int'(dut.int_len)-int'(dut.int_pos);
                if(check_n>4) check_n=4;
                check_end=int'(dut.int_pos)+check_n;
                check_needed=(check_end>int'(dut.a_len)) ? check_end-int'(dut.a_len) : 0;
                if(check_needed>produced_bytes)
                    $fatal(1,"integrity read uncommitted result bytes: needed=%0d produced=%0d",check_needed,produced_bytes);
            end
            if((dut.enc_in_valid && dut.enc_in_ready) != dut.u_result_buffer.wr_en)
                $fatal(1,"cipher input transfer and result-buffer write differ");
            if (dut.u_result_buffer.wr_en) begin
                if(int'(dut.u_result_buffer.wr_addr)!=produced_bytes ||
                   dut.u_result_buffer.wr_bytes==0 || dut.u_result_buffer.wr_bytes>4 ||
                   produced_bytes+int'(dut.u_result_buffer.wr_bytes)>int'(dut.enc_len))
                    $fatal(1,"noncontiguous or invalid cipher-result write");
                if(dut.mode_q==3'd2 && produced_bytes+int'(dut.u_result_buffer.wr_bytes)>int'(dut.b_len) && !dut.int_finished)
                    $fatal(1,"mode 2 encrypted MAC bytes before integrity completion");
                produced_bytes=produced_bytes+int'(dut.u_result_buffer.wr_bytes);
                if(!dut.int_finished) enc_before_int_done=enc_before_int_done+1;
            end
            if(dut.int_in_valid && dut.int_in_ready && !dut.enc_finished)
                int_before_enc_done=int_before_enc_done+1;
            if(dut.u_result_buffer.wr_en && dut.int_in_valid && dut.int_in_ready)
                overlap_cycles=overlap_cycles+1;
        end
    end

    reg enc_input_stalled=0,int_input_stalled=0;
    reg [31:0] held_enc_input=0,held_int_input=0;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            enc_input_stalled <= 0;
            int_input_stalled <= 0;
            held_enc_input <= 0;
            held_int_input <= 0;
        end else begin
            if(enc_input_stalled && (!dut.enc_in_valid || dut.enc_in!==held_enc_input))
                $fatal(1,"cipher input changed while stalled");
            if(int_input_stalled && (!dut.int_in_valid || dut.int_in!==held_int_input))
                $fatal(1,"integrity input changed while stalled");
            enc_input_stalled <= dut.enc_in_valid && !dut.enc_in_ready;
            int_input_stalled <= dut.int_in_valid && !dut.int_in_ready;
            if(dut.enc_in_valid && !dut.enc_in_ready) held_enc_input <= dut.enc_in;
            if(dut.int_in_valid && !dut.int_in_ready) held_int_input <= dut.int_in;
        end
    end

    integer fd,rc,id,mode,ca,ia,bearer,dir,alen,blen,mvalid,clen,rvalid,expected_match;
    reg [127:0] ck,ik;
    reg [31:0] count,expected_mac,expected_rx_mac;
    // Each of A and B has its own partial beat; ciphertext may append four bytes.
    reg [127:0] input_words[0:TEST_MAX_BYTES/16+2];
    reg [127:0] expected_words[0:TEST_MAX_BYTES/16+2];
    integer ni,no,i,idx,ticks,nb,expected_enc_bytes;
    reg [15:0] expected_keep;
    reg [127:0] held_word;
    reg [15:0] held_keep;
    reg held_last,stalled;
    string vector_path;

    task automatic reject_command(input [2:0] m, input [15:0] al, input [15:0] bl);
        begin
            @(negedge clk);
            if (!cmd_ready) $fatal(1,"not ready for invalid command");
            cmd_mode=m;
            cmd_a_bytes=al;
            cmd_b_bytes=bl;
            cmd_valid=1;
            @(posedge clk);
            @(negedge clk);
            cmd_valid=0;
            if (!rsp_valid || !rsp_error || rsp_cipher_bytes!=0 || rsp_mac_valid || in_ready ||
                rsp_mac!==0 || rsp_rx_mac!==0 || rsp_rx_mac_valid || rsp_mac_match)
                $fatal(1,"invalid descriptor not rejected cleanly");
            repeat(2) begin @(negedge clk);
                if(!rsp_valid || !rsp_error || cmd_ready) $fatal(1,"error response not held");
            end
            rsp_ready=1;
            @(posedge clk);
            @(negedge clk);
            rsp_ready=0;
            if(!cmd_ready || cipher_valid) $fatal(1,"invalid descriptor emitted data");
        end
    endtask

    // Abort each two-lane mode only after both lanes transfer on the same edge.
    // EEA0 produces long B quickly while EIA3 initializes and consumes A/B.
    task automatic abort_parallel(input [2:0] m);
        integer j,cycles;
        begin
            @(negedge clk);
            if(!cmd_ready) $fatal(1,"not ready for parallel reset setup");
            cmd_mode=m;
            cmd_cipher_alg=0;
            cmd_int_alg=3;
            cmd_cipher_key=0;
            cmd_int_key=0;
            cmd_count=0;
            cmd_bearer=0;
            cmd_direction=0;
            cmd_a_bytes=64;
            cmd_b_bytes=512;
            cmd_valid=1;
            @(posedge clk);
            @(negedge clk);
            cmd_valid=0;
            in_valid=1;
            for(j=0;
                j<36;
                j=j+1) begin
                in_data={4{32'(j)}};
                @(posedge clk);
                if(!in_ready) $fatal(1,"parallel reset setup input not ready");
                @(negedge clk);
            end
            in_valid=0;
            cycles=0;
            while(!(dut.u_result_buffer.wr_en && dut.int_in_valid && dut.int_in_ready)) begin
                @(negedge clk);
                cycles=cycles+1;
                if(cycles>2000) $fatal(1,"mode %0d parallel reset setup timed out",m);
            end
            @(posedge clk);
            @(negedge clk);
            if(dut.enc_pos==0 || dut.int_pos==0) $fatal(1,"no concurrent work before reset");
            rst_n=0;
            #1;
            if(cmd_ready || in_ready || rsp_valid || cipher_valid || rsp_rx_mac!==0 ||
               rsp_rx_mac_valid || rsp_mac_match || dut.enc_pos!=0 || dut.int_pos!=0)
                $fatal(1,"mode %0d parallel reset did not clear state",m);
            repeat(2) @(negedge clk);
            rst_n=1;
            @(negedge clk);
            if(!cmd_ready || rsp_valid || cipher_valid)
                $fatal(1,"mode %0d parallel reset did not abort packet",m);
        end
    endtask

    initial begin
        if (!$value$plusargs("VECTORS=%s",vector_path))
            $fatal(1,"pass +VECTORS=path");
        fd=$fopen(vector_path,"r");
        if (fd==0) $fatal(1,"cannot open %s",vector_path);
        for(i=2;
            i<=5;
            i=i+1) begin
            overlap_cases[i]=0;
            dependency_cases[i]=0;
            overlap_pair_mask[i]=0;
        end
        #1;
        if(cmd_ready || in_ready || rsp_valid || cipher_valid)
            $fatal(1,"interface must not advertise a handshake during reset");
        repeat(3) @(negedge clk);
        rst_n=1;
        if ($bits(in_data)!=128 || $bits(cipher_data)!=128 || $bits(cipher_keep)!=16 ||
            $bits(cmd_a_bytes)!=16 || $bits(cmd_b_bytes)!=16 || $bits(rsp_cipher_bytes)!=16 ||
            $bits(dut.a_len)!=16 || $bits(dut.b_len)!=16 || $bits(dut.total_len)!=16 ||
            $bits(dut.enc_len)!=16 || $bits(dut.int_len)!=16 || $bits(rsp_rx_mac)!=32 ||
            $bits(dut.cipher_len)!=16 || $bits(dut.load_n)!=16 || $bits(dut.out_n)!=16 ||
            $bits(dut.load_pos)!=16 || $bits(dut.enc_pos)!=16 || $bits(dut.int_pos)!=16 ||
            $bits(dut.out_pos)!=16 || $bits(dut.u_cipher.length)!=16 ||
            $bits(dut.u_cipher.left)!=16 || $bits(dut.u_cipher.issued)!=16 ||
            $bits(dut.u_cipher.out_bytes)!=16 || $bits(dut.u_integrity.length)!=16 ||
            $bits(dut.u_integrity.left)!=16 || $bits(dut.u_integrity.bytes_now)!=16 ||
            $bits(dut.u_integrity.used)!=16 || $bits(dut.u_input_buffer.wr_bytes)!=16)
            $fatal(1,"incorrect 128-bit data or 16-bit byte-count interface");
        reject_command(3'd6,16'd0,16'd0);
        reject_command(3'd7,16'd0,16'd0);
        // Mode 5 cannot extract a four-byte verification value from B<4.
        reject_command(3'd5,16'd0,16'd0);
        reject_command(3'd5,16'd0,16'd1);
        reject_command(3'd5,16'd0,16'd2);
        reject_command(3'd5,16'd0,16'd3);
        if (TEST_MAX_BYTES==2048) begin
            reject_command(3'd0,16'd2049,16'd0);
            reject_command(3'd4,16'd1800,16'd400);
        end
        if (TEST_MAX_BYTES==1)
            reject_command(3'd0,16'd0,16'd2);
        // Both wrapped A+B and wrapped mode-2 B+MAC must be rejected.
        // The B+MAC cases are especially important when MAX_BYTES=65535.
        reject_command(3'd0,16'd65535,16'd1);
        reject_command(3'd4,16'd65535,16'd65535);
        reject_command(3'd2,16'd0,16'd65532);
        reject_command(3'd2,16'd0,16'd65535);

        // Abort a running pair of stream ciphers. Reset must flush command,
        // result, control, and primitive state; following vectors prove restart.
        @(negedge clk);
        cmd_mode=4;
        cmd_cipher_alg=1;
        cmd_int_alg=3;
        cmd_a_bytes=0;
        cmd_b_bytes=(TEST_MAX_BYTES>=4) ? 16'd4 : 16'd1;
        cmd_valid=1;
        @(posedge clk);
        @(negedge clk);
        cmd_valid=0;
        in_valid=1;
        in_data=128'h12345678000000000000000000000000;
        @(posedge clk);
        @(negedge clk);
        in_valid=0;
        repeat(5) @(negedge clk);
        rst_n=0;
        repeat(3) @(negedge clk);
        rst_n=1;
        @(negedge clk);
        if(!cmd_ready || rsp_valid || cipher_valid) $fatal(1,"reset did not abort packet");

        // Reset after mode 5 has extracted its tag but before MAC completion.
        if(TEST_MAX_BYTES>=4) begin
            @(negedge clk);
            cmd_mode=5;
            cmd_cipher_alg=0;
            cmd_int_alg=1;
            cmd_a_bytes=0;
            cmd_b_bytes=4;
            cmd_valid=1;
            @(posedge clk);
            @(negedge clk);
            cmd_valid=0;
            in_data=128'h11223344000000000000000000000000;
            in_valid=1;
            @(posedge clk);
            @(negedge clk);
            in_valid=0;
            ticks=0;
            while(!rsp_rx_mac_valid) begin
                @(negedge clk);
                ticks=ticks+1;
                if(ticks>1000) $fatal(1,"mode 5 tag-capture setup timed out");
            end
            if(rsp_rx_mac!==32'h11223344 || rsp_valid)
                $fatal(1,"mode 5 tag-capture setup failed");
            rst_n=0;
            #1;
            if(rsp_rx_mac!==0 || rsp_rx_mac_valid || rsp_mac_match || cmd_ready || rsp_valid)
                $fatal(1,"reset did not clear the received verification code");
            repeat(3) @(negedge clk);
            rst_n=1;
            @(negedge clk);
            if(!cmd_ready || rsp_valid || cipher_valid) $fatal(1,"mode 5 reset did not abort packet");
        end

        if(TEST_MAX_BYTES>=576) begin
            abort_parallel(3'd2);
            abort_parallel(3'd3);
            abort_parallel(3'd4);
            abort_parallel(3'd5);
        end

        rc=$fscanf(fd,"%d %d %d %d %h %h %h %d %d %d %d %h %d %d %h %d %d\n",
                   id,mode,ca,ia,ck,ik,count,bearer,dir,alen,blen,expected_mac,mvalid,clen,expected_rx_mac,rvalid,expected_match);
        while (rc==17) begin
            ni=(alen+15)/16+(blen+15)/16;
            no=(clen+15)/16;
            expected_enc_bytes=(mode==5) ? blen : clen;
            for(i=0;
                i<ni;
                i=i+1) begin
                rc=$fscanf(fd,"%h\n",input_words[i]);
                if(rc!=1) $fatal(1,"input vector truncated");
            end
            for(i=0;
                i<no;
                i=i+1) begin
                rc=$fscanf(fd,"%h\n",expected_words[i]);
                if(rc!=1) $fatal(1,"output vector truncated");
            end
            @(negedge clk);
            if(!cmd_ready) $fatal(1,"case %0d command not ready",id);
            enc_started_at=-1;
            int_started_at=-1;
            enc_start_count=0;
            int_start_count=0;
            enc_done_at=-1;
            int_done_at=-1;
            rx_captured_at=-1;
            aes_issued_count=0;
            cmd_mode=3'(mode);
            cmd_cipher_alg=2'(ca);
            cmd_int_alg=2'(ia);
            cmd_cipher_key=ck;
            cmd_int_key=ik;
            cmd_count=count;
            cmd_bearer=5'(bearer);
            cmd_direction=1'(dir);
            cmd_a_bytes=16'(alen);
            cmd_b_bytes=16'(blen);
            cmd_valid=1;
            @(posedge clk);
            @(negedge clk);
            cmd_valid=0;
            // Descriptor fields may change immediately after the handshake.
            cmd_cipher_key=~ck;
            cmd_int_key=~ik;
            cmd_count=~count;
            cmd_mode=7;
            idx=0;
            ticks=0;
            while(idx<ni) begin
                @(negedge clk);
                in_valid=(ticks%5 != 1 && ticks%7 != 3);
                in_data=input_words[idx];
                ticks=ticks+1;
                @(posedge clk);
                if(in_valid && in_ready) idx=idx+1;
                if(ticks>(TEST_MAX_BYTES/16+3)*4+5000) $fatal(1,"case %0d input timeout",id);
            end
            @(negedge clk);
            in_valid=0;
            ticks=0;
            while(!rsp_valid) begin
                @(negedge clk);
                ticks=ticks+1;
                if(ticks>(TEST_MAX_BYTES+1)*4+4000)
                    $fatal(1,"case %0d response timeout mode=%0d ca=%0d ia=%0d",id,mode,ca,ia);
            end
            if(rsp_error || rsp_mac!==expected_mac || rsp_mac_valid!==1'(mvalid) ||
               rsp_cipher_bytes!==16'(clen) || rsp_rx_mac!==expected_rx_mac ||
               rsp_rx_mac_valid!==1'(rvalid) || rsp_mac_match!==1'(expected_match))
                $fatal(1,"case %0d rsp: mac=%h/%h valid=%b/%b len=%0d/%0d rx=%h/%h rv=%b/%b match=%b/%b err=%b mode=%0d ca=%0d ia=%0d a=%0d b=%0d",
                       id,rsp_mac,expected_mac,rsp_mac_valid,1'(mvalid),rsp_cipher_bytes,clen,
                       rsp_rx_mac,expected_rx_mac,rsp_rx_mac_valid,1'(rvalid),
                       rsp_mac_match,1'(expected_match),rsp_error,mode,ca,ia,alen,blen);
            if(mode>=2 && mode<=5 && !(enc_started_at>=0 && enc_started_at==int_started_at &&
                                      enc_start_count==1 && int_start_count==1))
                $fatal(1,"case %0d mode %0d lanes did not start exactly once on the same edge",id,mode);
            if(mode==5 && !(enc_done_at>=0 && rx_captured_at==enc_done_at))
                $fatal(1,"case %0d mode 5 tag not captured at cipher completion",id);
            // Long directed cases must do real data work concurrently, not
            // merely pulse both start signals and serialize the processing.
            if(TEST_MAX_BYTES==2048 &&
               ((mode==2 && alen==1023 && blen==1025) ||
                (mode==3 && alen==1 && blen==2047) ||
                (mode==4 && alen==777 && blen==1271) ||
                (mode==5 && blen==2048-alen && (alen==14 || alen==27 || alen==40)))) begin
                if(overlap_cycles==0)
                    $fatal(1,"case %0d mode %0d has no simultaneous lane transfers",id,mode);
                if(mode==2 && enc_before_int_done==0)
                    $fatal(1,"case %0d mode 2 did not encrypt before MAC completion",id);
                if((mode==3 || mode==5) && int_before_enc_done==0)
                    $fatal(1,"case %0d mode %0d did not authenticate before cipher completion",id,mode);
            end
            // Systematically cover all 4 cipher x 3 non-null integrity pairs.
            if(TEST_MAX_BYTES==2048 && ia!=0 &&
               ((mode==2 && alen==321 && blen==703) ||
                (mode==3 && alen==1 && blen==1023) ||
                (mode==4 && alen==397 && blen==627) ||
                (mode==5 && alen==3 && blen==1021))) begin
                if(overlap_cycles==0)
                    $fatal(1,"case %0d mode %0d alg %0d/%0d has no simultaneous transfers",id,mode,ca,ia);
                if(mode==2 && (enc_before_int_done==0 || wait_for_mac==0))
                    $fatal(1,"case %0d mode 2 did not both overlap and wait for the MAC",id);
                if((mode==3 || mode==5) && int_before_enc_done==0)
                    $fatal(1,"case %0d mode %0d did not authenticate before cipher completion",id,mode);
                overlap_cases[mode]=overlap_cases[mode]+1;
                overlap_pair_mask[mode][ca*3+ia-1]=1'b1;
                if((mode==2 && wait_for_mac!=0) ||
                   ((mode==3 || mode==5) && wait_for_result!=0))
                    dependency_cases[mode]=dependency_cases[mode]+1;
            end
            if(mode!=1 && ca==2 &&
               (aes_issued_count!=(expected_enc_bytes+15)/16 || dut.u_cipher.issued!==16'(expected_enc_bytes)))
                $fatal(1,"case %0d AES block count/byte counter: issued=%0d expected=%0d counter=%0d length=%0d",
                       id,aes_issued_count,(expected_enc_bytes+15)/16,dut.u_cipher.issued,expected_enc_bytes);
            if(mode==0 && int_started_at!=-1) $fatal(1,"case %0d unexpected integrity start",id);
            if(mode==1 && enc_started_at!=-1) $fatal(1,"case %0d unexpected cipher start",id);
            repeat(3) begin
                @(negedge clk);
                if(!rsp_valid || rsp_error || rsp_mac!==expected_mac || rsp_mac_valid!==1'(mvalid) ||
                   rsp_cipher_bytes!==16'(clen) || rsp_rx_mac!==expected_rx_mac ||
                   rsp_rx_mac_valid!==1'(rvalid) || rsp_mac_match!==1'(expected_match) || cmd_ready)
                    $fatal(1,"case %0d response unstable under backpressure",id);
            end
            rsp_ready=1;
            @(posedge clk);
            @(negedge clk);
            rsp_ready=0;
            idx=0;
            ticks=0;
            stalled=0;
            while(idx<no) begin
                cipher_ready=(ticks%7>=3);
                ticks=ticks+1;
                @(posedge clk);
                if(!cipher_valid) $fatal(1,"case %0d missing cipher beat %0d",id,idx);
                nb=(clen-16*idx>=16) ? 16 : clen-16*idx;
                expected_keep=16'hffff << (16-nb);
                if(cipher_data!==expected_words[idx] || cipher_keep!==expected_keep || cipher_last!==(idx==no-1))
                    $fatal(1,"case %0d beat %0d got=%h keep=%b last=%b expected=%h keep=%b last=%b mode=%0d ca=%0d ia=%0d a=%0d b=%0d",
                           id,idx,cipher_data,cipher_keep,cipher_last,expected_words[idx],expected_keep,(idx==no-1),mode,ca,ia,alen,blen);
                if(stalled && (cipher_data!==held_word || cipher_keep!==held_keep || cipher_last!==held_last))
                    $fatal(1,"case %0d output changed under stall",id);
                stalled=!cipher_ready;
                if(stalled) begin held_word=cipher_data;
                    held_keep=cipher_keep;
                    held_last=cipher_last;
                end
                if(cipher_ready) idx=idx+1;
                @(negedge clk);
                if(ticks>(TEST_MAX_BYTES/16+3)*4+5000) $fatal(1,"case %0d output timeout",id);
            end
            cipher_ready=0;
            if(!cmd_ready || cipher_valid) $fatal(1,"case %0d did not finish",id);
            rc=$fscanf(fd,"%d %d %d %d %h %h %h %d %d %d %d %h %d %d %h %d %d\n",
                       id,mode,ca,ia,ck,ik,count,bearer,dir,alen,blen,expected_mac,mvalid,clen,expected_rx_mac,rvalid,expected_match);
        end
        if(rc!=-1) $fatal(1,"bad vector header: fscanf=%0d",rc);
        $fclose(fd);
        if(TEST_MAX_BYTES==2048 && $test$plusargs("REQUIRE_PARALLEL_COVERAGE")) begin
            for(i=2;
                i<=5;
                i=i+1)
                if(overlap_pair_mask[i]!==12'hfff)
                    $fatal(1,"mode %0d parallel algorithm coverage incomplete: mask=%h cases=%0d",
                           i,overlap_pair_mask[i],overlap_cases[i]);
            if(dependency_cases[2]==0 || dependency_cases[3]==0 || dependency_cases[5]==0)
                $fatal(1,"dependency wait coverage incomplete: %0d/%0d/%0d",
                       dependency_cases[2],dependency_cases[3],dependency_cases[5]);
            $display("PASS simultaneous transfers by mode 2/3/4/5: %0d/%0d/%0d/%0d; dependency waits 2/3/5: %0d/%0d/%0d",
                     overlap_cases[2],overlap_cases[3],overlap_cases[4],overlap_cases[5],
                     dependency_cases[2],dependency_cases[3],dependency_cases[5]);
        end
        // Also abort a held output. Stale RAM contents must not be exposed
        // on the external data bus after reset while cipher_valid is low.
        @(negedge clk);
        cmd_mode=0;
        cmd_cipher_alg=0;
        cmd_a_bytes=0;
        cmd_b_bytes=(TEST_MAX_BYTES>=4) ? 16'd4 : 16'd1;
        cmd_valid=1;
        @(posedge clk);
        @(negedge clk);
        cmd_valid=0;
        in_data=128'hcafebabe000000000000000000000000;
        in_valid=1;
        @(posedge clk);
        @(negedge clk);
        in_valid=0;
        while(!rsp_valid) @(negedge clk);
        if(rsp_rx_mac!==0 || rsp_rx_mac_valid || rsp_mac_match)
            $fatal(1,"received verification code leaked into a later mode");
        rsp_ready=1;
        @(posedge clk);
        @(negedge clk);
        rsp_ready=0;
        if(!cipher_valid ||
           (TEST_MAX_BYTES>=4 && cipher_data!==128'hcafebabe000000000000000000000000) ||
           (TEST_MAX_BYTES<4 && cipher_data!==128'hca000000000000000000000000000000))
            $fatal(1,"reset-output setup failed");
        rst_n=0;
        #1;
        if(cmd_ready || in_ready || rsp_valid || cipher_valid ||
           cipher_data!==0 || cipher_keep!==0 || cipher_last)
            $fatal(1,"reset exposed stale output or advertised a handshake");
        repeat(2) @(negedge clk);
        rst_n=1;
        @(negedge clk);
        if(!cmd_ready || rsp_valid || cipher_valid) $fatal(1,"output reset did not abort packet");
        $display("PASS %0d packet vectors (MAX_BYTES=%0d), stalls, reset, length rejection, and AES block counts",id+1,TEST_MAX_BYTES);
        $finish;
    end
    initial begin #30000000;
        $fatal(1,"packet test timeout");
    end
endmodule
