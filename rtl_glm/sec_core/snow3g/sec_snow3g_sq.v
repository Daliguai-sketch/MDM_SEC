//============================================================================
// Module : sec_snow3g_sq
// Desc   : SNOW 3G SQ S-box lookup table. From Python SQ[] in sec_snow3g_core.py.
//============================================================================
module sec_snow3g_sq (
    input  wire [7:0] i_addr,
    output wire [7:0] o_dout
);
    reg [7:0] sq_mem [0:255];
    initial begin
        sq_mem[8'h00]=8'h25; sq_mem[8'h01]=8'h24; sq_mem[8'h02]=8'h73; sq_mem[8'h03]=8'h67;
        sq_mem[8'h04]=8'hD7; sq_mem[8'h05]=8'hAE; sq_mem[8'h06]=8'h5C; sq_mem[8'h07]=8'h30;
        sq_mem[8'h08]=8'hA4; sq_mem[8'h09]=8'hEE; sq_mem[8'h0A]=8'h6E; sq_mem[8'h0B]=8'hCB;
        sq_mem[8'h0C]=8'h7D; sq_mem[8'h0D]=8'hB5; sq_mem[8'h0E]=8'h82; sq_mem[8'h0F]=8'hDB;
        sq_mem[8'h10]=8'hE4; sq_mem[8'h11]=8'h8E; sq_mem[8'h12]=8'h48; sq_mem[8'h13]=8'h49;
        sq_mem[8'h14]=8'h4F; sq_mem[8'h15]=8'h5D; sq_mem[8'h16]=8'h6A; sq_mem[8'h17]=8'h78;
        sq_mem[8'h18]=8'h70; sq_mem[8'h19]=8'h88; sq_mem[8'h1A]=8'hE8; sq_mem[8'h1B]=8'h5F;
        sq_mem[8'h1C]=8'h5E; sq_mem[8'h1D]=8'h84; sq_mem[8'h1E]=8'h65; sq_mem[8'h1F]=8'hE2;
        sq_mem[8'h20]=8'hD8; sq_mem[8'h21]=8'hE9; sq_mem[8'h22]=8'hCC; sq_mem[8'h23]=8'hED;
        sq_mem[8'h24]=8'h40; sq_mem[8'h25]=8'h2F; sq_mem[8'h26]=8'h11; sq_mem[8'h27]=8'h28;
        sq_mem[8'h28]=8'h57; sq_mem[8'h29]=8'hD2; sq_mem[8'h2A]=8'hAC; sq_mem[8'h2B]=8'hE3;
        sq_mem[8'h2C]=8'h4A; sq_mem[8'h2D]=8'h15; sq_mem[8'h2E]=8'h1B; sq_mem[8'h2F]=8'hB9;
        sq_mem[8'h30]=8'hB2; sq_mem[8'h31]=8'h80; sq_mem[8'h32]=8'h85; sq_mem[8'h33]=8'hA6;
        sq_mem[8'h34]=8'h2E; sq_mem[8'h35]=8'h02; sq_mem[8'h36]=8'h47; sq_mem[8'h37]=8'h29;
        sq_mem[8'h38]=8'h07; sq_mem[8'h39]=8'h4B; sq_mem[8'h3A]=8'h0E; sq_mem[8'h3B]=8'hC1;
        sq_mem[8'h3C]=8'h51; sq_mem[8'h3D]=8'hAA; sq_mem[8'h3E]=8'h89; sq_mem[8'h3F]=8'hD4;
        sq_mem[8'h40]=8'hCA; sq_mem[8'h41]=8'h01; sq_mem[8'h42]=8'h46; sq_mem[8'h43]=8'hB3;
        sq_mem[8'h44]=8'hEF; sq_mem[8'h45]=8'hDD; sq_mem[8'h46]=8'h44; sq_mem[8'h47]=8'h7B;
        sq_mem[8'h48]=8'hC2; sq_mem[8'h49]=8'h7F; sq_mem[8'h4A]=8'hBE; sq_mem[8'h4B]=8'hC3;
        sq_mem[8'h4C]=8'h9F; sq_mem[8'h4D]=8'h20; sq_mem[8'h4E]=8'h4C; sq_mem[8'h4F]=8'h64;
        sq_mem[8'h50]=8'h83; sq_mem[8'h51]=8'hA2; sq_mem[8'h52]=8'h68; sq_mem[8'h53]=8'h42;
        sq_mem[8'h54]=8'h13; sq_mem[8'h55]=8'hB4; sq_mem[8'h56]=8'h41; sq_mem[8'h57]=8'hCD;
        sq_mem[8'h58]=8'hBA; sq_mem[8'h59]=8'hC6; sq_mem[8'h5A]=8'hBB; sq_mem[8'h5B]=8'h6D;
        sq_mem[8'h5C]=8'h4D; sq_mem[8'h5D]=8'h71; sq_mem[8'h5E]=8'h21; sq_mem[8'h5F]=8'hF4;
        sq_mem[8'h60]=8'h8D; sq_mem[8'h61]=8'hB0; sq_mem[8'h62]=8'hE5; sq_mem[8'h63]=8'h93;
        sq_mem[8'h64]=8'hFE; sq_mem[8'h65]=8'h8F; sq_mem[8'h66]=8'hE6; sq_mem[8'h67]=8'hCF;
        sq_mem[8'h68]=8'h43; sq_mem[8'h69]=8'h45; sq_mem[8'h6A]=8'h31; sq_mem[8'h6B]=8'h22;
        sq_mem[8'h6C]=8'h37; sq_mem[8'h6D]=8'h36; sq_mem[8'h6E]=8'h96; sq_mem[8'h6F]=8'hFA;
        sq_mem[8'h70]=8'hBC; sq_mem[8'h71]=8'h0F; sq_mem[8'h72]=8'h08; sq_mem[8'h73]=8'h52;
        sq_mem[8'h74]=8'h1D; sq_mem[8'h75]=8'h55; sq_mem[8'h76]=8'h1A; sq_mem[8'h77]=8'hC5;
        sq_mem[8'h78]=8'h4E; sq_mem[8'h79]=8'h23; sq_mem[8'h7A]=8'h69; sq_mem[8'h7B]=8'h7A;
                sq_mem[8'h7C]=8'h92; sq_mem[8'h7D]=8'hFF; sq_mem[8'h7E]=8'h5B; sq_mem[8'h7F]=8'h5A;
        sq_mem[8'h80]=8'hEB; sq_mem[8'h81]=8'h9A; sq_mem[8'h82]=8'h1C; sq_mem[8'h83]=8'hA9;
        sq_mem[8'h84]=8'hD1; sq_mem[8'h85]=8'h7E; sq_mem[8'h86]=8'h0D; sq_mem[8'h87]=8'hFC;
        sq_mem[8'h88]=8'h50; sq_mem[8'h89]=8'h8A; sq_mem[8'h8A]=8'hB6; sq_mem[8'h8B]=8'h62;
        sq_mem[8'h8C]=8'hF5; sq_mem[8'h8D]=8'h0A; sq_mem[8'h8E]=8'hF8; sq_mem[8'h8F]=8'hDC;
        sq_mem[8'h90]=8'h03; sq_mem[8'h91]=8'h3C; sq_mem[8'h92]=8'h0C; sq_mem[8'h93]=8'h39;
        sq_mem[8'h94]=8'hF1; sq_mem[8'h95]=8'hB8; sq_mem[8'h96]=8'hF3; sq_mem[8'h97]=8'h3D;
        sq_mem[8'h98]=8'hF2; sq_mem[8'h99]=8'hD5; sq_mem[8'h9A]=8'h97; sq_mem[8'h9B]=8'h66;
        sq_mem[8'h9C]=8'h81; sq_mem[8'h9D]=8'h32; sq_mem[8'h9E]=8'hA0; sq_mem[8'h9F]=8'h00;
        sq_mem[8'hA0]=8'h06; sq_mem[8'hA1]=8'hCE; sq_mem[8'hA2]=8'hF6; sq_mem[8'hA3]=8'hEA;
        sq_mem[8'hA4]=8'hB7; sq_mem[8'hA5]=8'h17; sq_mem[8'hA6]=8'hF7; sq_mem[8'hA7]=8'h8C;
        sq_mem[8'hA8]=8'h79; sq_mem[8'hA9]=8'hD6; sq_mem[8'hAA]=8'hA7; sq_mem[8'hAB]=8'hBF;
        sq_mem[8'hAC]=8'h8B; sq_mem[8'hAD]=8'h3F; sq_mem[8'hAE]=8'h1F; sq_mem[8'hAF]=8'h53;
        sq_mem[8'hB0]=8'h63; sq_mem[8'hB1]=8'h75; sq_mem[8'hB2]=8'h35; sq_mem[8'hB3]=8'h2C;
        sq_mem[8'hB4]=8'h60; sq_mem[8'hB5]=8'hFD; sq_mem[8'hB6]=8'h27; sq_mem[8'hB7]=8'hD3;
        sq_mem[8'hB8]=8'h94; sq_mem[8'hB9]=8'hA5; sq_mem[8'hBA]=8'h7C; sq_mem[8'hBB]=8'hA1;
        sq_mem[8'hBC]=8'h05; sq_mem[8'hBD]=8'h58; sq_mem[8'hBE]=8'h2D; sq_mem[8'hBF]=8'hBD;
        sq_mem[8'hC0]=8'hD9; sq_mem[8'hC1]=8'hC7; sq_mem[8'hC2]=8'hAF; sq_mem[8'hC3]=8'h6B;
        sq_mem[8'hC4]=8'h54; sq_mem[8'hC5]=8'h0B; sq_mem[8'hC6]=8'hE0; sq_mem[8'hC7]=8'h38;
        sq_mem[8'hC8]=8'h04; sq_mem[8'hC9]=8'hC8; sq_mem[8'hCA]=8'h9D; sq_mem[8'hCB]=8'hE7;
        sq_mem[8'hCC]=8'h14; sq_mem[8'hCD]=8'hB1; sq_mem[8'hCE]=8'h87; sq_mem[8'hCF]=8'h9C;
        sq_mem[8'hD0]=8'hDF; sq_mem[8'hD1]=8'h6F; sq_mem[8'hD2]=8'hF9; sq_mem[8'hD3]=8'hDA;
        sq_mem[8'hD4]=8'h2A; sq_mem[8'hD5]=8'hC4; sq_mem[8'hD6]=8'h59; sq_mem[8'hD7]=8'h16;
        sq_mem[8'hD8]=8'h74; sq_mem[8'hD9]=8'h91; sq_mem[8'hDA]=8'hAB; sq_mem[8'hDB]=8'h26;
        sq_mem[8'hDC]=8'h61; sq_mem[8'hDD]=8'h76; sq_mem[8'hDE]=8'h34; sq_mem[8'hDF]=8'h2B;
        sq_mem[8'hE0]=8'hAD; sq_mem[8'hE1]=8'h99; sq_mem[8'hE2]=8'hFB; sq_mem[8'hE3]=8'h72;
        sq_mem[8'hE4]=8'hEC; sq_mem[8'hE5]=8'h33; sq_mem[8'hE6]=8'h12; sq_mem[8'hE7]=8'hDE;
        sq_mem[8'hE8]=8'h98; sq_mem[8'hE9]=8'h3B; sq_mem[8'hEA]=8'hC0; sq_mem[8'hEB]=8'h9B;
        sq_mem[8'hEC]=8'h3E; sq_mem[8'hED]=8'h18; sq_mem[8'hEE]=8'h10; sq_mem[8'hEF]=8'h3A;
        sq_mem[8'hF0]=8'h56; sq_mem[8'hF1]=8'hE1; sq_mem[8'hF2]=8'h77; sq_mem[8'hF3]=8'hC9;
        sq_mem[8'hF4]=8'h1E; sq_mem[8'hF5]=8'h9E; sq_mem[8'hF6]=8'h95; sq_mem[8'hF7]=8'hA3;
        sq_mem[8'hF8]=8'h90; sq_mem[8'hF9]=8'h19; sq_mem[8'hFA]=8'hA8; sq_mem[8'hFB]=8'h6C;
        sq_mem[8'hFC]=8'h09; sq_mem[8'hFD]=8'hD0; sq_mem[8'hFE]=8'hF0; sq_mem[8'hFF]=8'h86;
    end
    assign o_dout = sq_mem[i_addr];
endmodule
