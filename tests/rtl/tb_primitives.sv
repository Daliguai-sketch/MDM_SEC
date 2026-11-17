`timescale 1ns/1ps
module tb_primitives;
  `include "mdm_aes_sbox.vh"
  reg [7:0] expected_sbox[0:255];
  string sbox_path;
  reg clk=0, rst_n=0;
  always #5 clk=~clk;
  reg aes_start=0;
  wire aes_ready,aes_busy,aes_done;
  reg [127:0] aes_key=0,aes_input=0;
  wire [127:0] aes_output;
  mdm_aes128 aes(clk,rst_n,aes_start,aes_ready,aes_key,aes_input,aes_busy,aes_done,aes_output);

  reg stream_start=0,advance=0;
  wire sv,zv;
  wire [31:0] sw,zw;
  mdm_snow3g snow(clk,rst_n,stream_start,
      128'hd3c5d592327fb11c4035c6680af8c6d1,
      128'h398a59b4ac000000398a59b4ac000000,advance,sv,sw);
  mdm_zuc zuc(clk,rst_n,stream_start,128'b0,128'b0,advance,zv,zw);
  reg [31:0] snow_expect[0:2];
  reg [31:0] zuc_expect[0:2];
  integer i;
  initial begin
    if (!$value$plusargs("SBOX=%s",sbox_path)) sbox_path="tests/rtl/aes_sbox.hex";
    $readmemh(sbox_path,expected_sbox);
    for(i=0;
        i<256;
        i=i+1)
      if(aes_sbox(8'(i))!==expected_sbox[i]) $fatal(1,"AES S-box mismatch at %0d",i);
    snow_expect[0]=32'hc54058f7;
    snow_expect[1]=32'ha71f0d96;
    snow_expect[2]=32'h54246457;
    zuc_expect[0]=32'h27bede74;
    zuc_expect[1]=32'h018082da;
    zuc_expect[2]=32'h87d4e5b6;
    repeat(3) @(negedge clk);
    rst_n=1;
    // FIPS-197 AES-128 example; launch the identical second block at the
    // earliest legal edge, verifying both five-cycle latency and interval.
    @(negedge clk);
    aes_key=128'h000102030405060708090a0b0c0d0e0f;
    aes_input=128'h00112233445566778899aabbccddeeff;
    aes_start=1;
    @(posedge clk);
    #1;
    @(negedge clk);
    aes_start=0;
    for(i=1;
        i<5;
        i=i+1) begin
      @(posedge clk);
      #1;
      if (aes_done) $fatal(1,"AES completed before cycle 5");
    end
    @(negedge clk);
    if (!aes_ready) $fatal(1,"AES cannot accept at the five-cycle boundary");
    aes_start=1;
    @(posedge clk);
    #1;
    if (!aes_done || aes_output!==128'h69c4e0d86a7b0430d8cdb78070b4c55a)
      $fatal(1,"AES first block/latency failed: %h",aes_output);
    @(negedge clk);
    aes_start=0;
    for(i=1;
        i<5;
        i=i+1) begin
      @(posedge clk);
      #1;
      if (aes_done) $fatal(1,"second AES completed early");
    end
    @(posedge clk);
    #1;
    if (!aes_done || aes_output!==128'h69c4e0d86a7b0430d8cdb78070b4c55a)
      $fatal(1,"AES second block/interval failed");

    // SNOW vector is the keystream recovered from 3GPP EEA1 set 1;
    // ZUC uses the published all-zero key/IV primitive vector.
    @(negedge clk);
    stream_start=1;
    @(posedge clk);
    #1;
    @(negedge clk);
    stream_start=0;
    for(i=1;
        i<=33;
        i=i+1) begin
      @(posedge clk);
      #1;
      if(i<33 && (sv || zv)) $fatal(1,"stream became valid during init");
    end
    if (!sv || !zv || sw!==snow_expect[0] || zw!==zuc_expect[0])
      $fatal(1,"first stream word mismatch snow=%h zuc=%h",sw,zw);
    // Both generators must hold a word while not advanced.
    repeat(4) begin @(posedge clk);
        #1;
      if(sw!==snow_expect[0] || zw!==zuc_expect[0]) $fatal(1,"stall changed keystream");
    end
    @(negedge clk);
    advance=1;
    for(i=0;
        i<3;
        i=i+1) begin
      @(posedge clk);
      if(!sv || !zv || sw!==snow_expect[i] || zw!==zuc_expect[i])
        $fatal(1,"stream word %0d snow=%h zuc=%h",i,sw,zw);
    end
    @(negedge clk);
    advance=0;
    $display("PASS primitive AES latency/II and SNOW3G/ZUC init, stall, 1 word/cycle");
    $finish;
  end
  initial begin #100000;
      $fatal(1,"primitive test timeout");
  end
endmodule
