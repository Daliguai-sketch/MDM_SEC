`timescale 1ns/1ps
// Compare every balanced-opt datapath stage with independent Python AES
// vectors, including all Rcon bytes and both ordinary/final-round outputs.
module tb_aes_balanced_blocks;
    reg [127:0] state_in, key_in;
    reg [7:0] rcon, rcon2;
    reg last_round;
    wire [127:0] sub, shifted, mixed, added, initial_state;
    wire [127:0] key1, key2, round_normal, disabled_last, timing_normal, timing_last;
    reg [127:0] expected_sub, expected_shifted, expected_mixed;
    reg [127:0] expected_normal, expected_last, expected_key1, expected_key2;
    reg [255:0] seen_rcon=0;
    integer fd, rc, count=0, ordinary=0, last=0;
    string vector_path;

    mdm_aes_balanced_subbytes_timing u_subbytes (.state_in(state_in), .state_out(sub));
    mdm_aes_shift_rows u_shift_rows (.state_in(sub), .state_out(shifted));
    mdm_aes_balanced_mix_columns_timing u_mix_columns (.state_in(shifted), .state_out(mixed));
    mdm_aes_balanced_add_round_key u_add_round_key (
        .state_in(mixed), .round_key(key1), .state_out(added)
    );
    mdm_aes_balanced_add_round_key u_initial_add_round_key (
        .state_in(state_in), .round_key(key_in), .state_out(initial_state)
    );
    mdm_aes_balanced_key_expand1 u_key_expand1 (
        .key_in(key_in), .rcon(rcon), .key_out(key1)
    );
    mdm_aes_balanced_key_expand2 u_key_expand2 (
        .key_in(key_in), .key1(key1), .rcon(rcon2), .key_out(key2)
    );
    // The first round has no last-round output; the second produces the
    // ordinary feedback and bypassed last-round result concurrently.
    mdm_aes_balanced_round_timing #(.WITH_LAST_OUTPUT(0)) u_round_normal (
        .state_in(state_in), .round_key(key1), .normal_out(round_normal), .last_out(disabled_last)
    );
    mdm_aes_balanced_round_timing #(.WITH_LAST_OUTPUT(1)) u_timing_round (
        .state_in(state_in), .round_key(key1), .normal_out(timing_normal), .last_out(timing_last)
    );

    initial begin
        if (!$value$plusargs("VECTORS=%s",vector_path))
            $fatal(1,"pass +VECTORS=path");
        fd=$fopen(vector_path,"r");
        if (fd==0) $fatal(1,"cannot open AES intermediate vectors");
        rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h\n",
                   state_in,key_in,rcon,rcon2,last_round,expected_sub,expected_shifted,
                   expected_mixed,expected_normal,expected_last,expected_key1,expected_key2);
        while (rc==12) begin
            #1;
            if (sub!==expected_sub) $fatal(1,"SubBytes mismatch at vector %0d",count);
            if (shifted!==expected_shifted) $fatal(1,"ShiftRows mismatch at vector %0d",count);
            if (mixed!==expected_mixed) $fatal(1,"MixColumns mismatch at vector %0d",count);
            if (initial_state!==(state_in ^ key_in)) $fatal(1,"initial AddRoundKey mismatch at %0d",count);
            if (key1!==expected_key1) $fatal(1,"first expanded key mismatch at vector %0d",count);
            if (key2!==expected_key2) $fatal(1,"second expanded key mismatch at vector %0d",count);
            if (added!==expected_normal || round_normal!==expected_normal || disabled_last!==128'b0)
                $fatal(1,"first normal round mismatch at vector %0d",count);
            if (timing_normal!==expected_normal || timing_last!==expected_last)
                $fatal(1,"normal/final round mismatch at vector %0d",count);
            seen_rcon[rcon]=1'b1;
            if (last_round) last=last+1;
            else ordinary=ordinary+1;
            count=count+1;
            rc=$fscanf(fd,"%h %h %h %h %h %h %h %h %h %h %h %h\n",
                       state_in,key_in,rcon,rcon2,last_round,expected_sub,expected_shifted,
                       expected_mixed,expected_normal,expected_last,expected_key1,expected_key2);
        end
        if (rc!=-1 || count<512 || ordinary<256 || last<256 || !(&seen_rcon))
            $fatal(1,"bad or insufficient AES intermediate vectors");
        $fclose(fd);
        $display("PASS %0d Python-model AES stage vectors, all Rcon values and final-round bypass",count);
        $finish;
    end
endmodule
