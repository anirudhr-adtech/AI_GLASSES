`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////
// AI_GLASSES — Audio Subsystem
// Module: log_lut_rom
// Description: 256-entry natural log lookup table. Maps 8-bit mantissa index
//              to 16-bit log value (Q8.8 fixed-point).
//              log(x) for x in [0.5, 1.0) mapped to 256 entries.
//////////////////////////////////////////////////////////////////////////////

module log_lut_rom (
    input  wire        clk,
    input  wire [7:0]  addr_i,
    output reg  [15:0] data_o
);

    // LUT: ln(1 + i/256) * 256, stored as Q8.8
    // For mantissa m in [0.5, 1.0): index = (m - 0.5) * 512
    // Value = ln(0.5 + index/512) in Q8.8
    // ln(0.5) = -0.6931 -> Q8.8 = 0xFF4D (signed)
    // ln(1.0) = 0.0     -> Q8.8 = 0x0000
    reg [15:0] lut [0:255];

    // Populate with ln(0.5 + i/512) in Q8.8 signed format
    // Q8.8: value = real * 256
    // ln(0.5)   = -0.6931 * 256 = -177.4 -> 16'hFF4F
    // ln(0.75)  = -0.2877 * 256 = -73.6  -> 16'hFFB7
    // ln(1.0)   =  0.0    * 256 =  0     -> 16'h0000
    initial begin
        // Generated: lut[i] = round(ln(0.5 + i/512) * 256) as signed Q8.8
        lut[  0] = 16'hFF4F; // ln(0.5000) = -0.6931
        lut[  1] = 16'hFF50; // ln(0.5020)
        lut[  2] = 16'hFF51;
        lut[  3] = 16'hFF52;
        lut[  4] = 16'hFF53;
        lut[  5] = 16'hFF55;
        lut[  6] = 16'hFF56;
        lut[  7] = 16'hFF57;
        lut[  8] = 16'hFF58;
        lut[  9] = 16'hFF59;
        lut[ 10] = 16'hFF5B;
        lut[ 11] = 16'hFF5C;
        lut[ 12] = 16'hFF5D;
        lut[ 13] = 16'hFF5E;
        lut[ 14] = 16'hFF60;
        lut[ 15] = 16'hFF61;
        lut[ 16] = 16'hFF62; // ln(0.5312)
        lut[ 17] = 16'hFF63;
        lut[ 18] = 16'hFF65;
        lut[ 19] = 16'hFF66;
        lut[ 20] = 16'hFF67;
        lut[ 21] = 16'hFF69;
        lut[ 22] = 16'hFF6A;
        lut[ 23] = 16'hFF6B;
        lut[ 24] = 16'hFF6D;
        lut[ 25] = 16'hFF6E;
        lut[ 26] = 16'hFF6F;
        lut[ 27] = 16'hFF71;
        lut[ 28] = 16'hFF72;
        lut[ 29] = 16'hFF73;
        lut[ 30] = 16'hFF75;
        lut[ 31] = 16'hFF76;
        lut[ 32] = 16'hFF78; // ln(0.5625)
        lut[ 33] = 16'hFF79;
        lut[ 34] = 16'hFF7A;
        lut[ 35] = 16'hFF7C;
        lut[ 36] = 16'hFF7D;
        lut[ 37] = 16'hFF7F;
        lut[ 38] = 16'hFF80;
        lut[ 39] = 16'hFF81;
        lut[ 40] = 16'hFF83;
        lut[ 41] = 16'hFF84;
        lut[ 42] = 16'hFF86;
        lut[ 43] = 16'hFF87;
        lut[ 44] = 16'hFF89;
        lut[ 45] = 16'hFF8A;
        lut[ 46] = 16'hFF8C;
        lut[ 47] = 16'hFF8D;
        lut[ 48] = 16'hFF8E; // ln(0.5938)
        lut[ 49] = 16'hFF90;
        lut[ 50] = 16'hFF91;
        lut[ 51] = 16'hFF93;
        lut[ 52] = 16'hFF94;
        lut[ 53] = 16'hFF96;
        lut[ 54] = 16'hFF97;
        lut[ 55] = 16'hFF99;
        lut[ 56] = 16'hFF9A;
        lut[ 57] = 16'hFF9C;
        lut[ 58] = 16'hFF9D;
        lut[ 59] = 16'hFF9F;
        lut[ 60] = 16'hFFA0;
        lut[ 61] = 16'hFFA2;
        lut[ 62] = 16'hFFA3;
        lut[ 63] = 16'hFFA5;
        lut[ 64] = 16'hFFA6; // ln(0.625)
        lut[ 65] = 16'hFFA8;
        lut[ 66] = 16'hFFA9;
        lut[ 67] = 16'hFFAB;
        lut[ 68] = 16'hFFAC;
        lut[ 69] = 16'hFFAE;
        lut[ 70] = 16'hFFAF;
        lut[ 71] = 16'hFFB1;
        lut[ 72] = 16'hFFB2;
        lut[ 73] = 16'hFFB4;
        lut[ 74] = 16'hFFB5;
        lut[ 75] = 16'hFFB7;
        lut[ 76] = 16'hFFB8;
        lut[ 77] = 16'hFFBA;
        lut[ 78] = 16'hFFBB;
        lut[ 79] = 16'hFFBD;
        lut[ 80] = 16'hFFBE; // ln(0.6562)
        lut[ 81] = 16'hFFC0;
        lut[ 82] = 16'hFFC1;
        lut[ 83] = 16'hFFC3;
        lut[ 84] = 16'hFFC4;
        lut[ 85] = 16'hFFC6;
        lut[ 86] = 16'hFFC7;
        lut[ 87] = 16'hFFC9;
        lut[ 88] = 16'hFFCA;
        lut[ 89] = 16'hFFCC;
        lut[ 90] = 16'hFFCD;
        lut[ 91] = 16'hFFCF;
        lut[ 92] = 16'hFFD0;
        lut[ 93] = 16'hFFD2;
        lut[ 94] = 16'hFFD3;
        lut[ 95] = 16'hFFD5;
        lut[ 96] = 16'hFFD6; // ln(0.6875)
        lut[ 97] = 16'hFFD8;
        lut[ 98] = 16'hFFD9;
        lut[ 99] = 16'hFFDB;
        lut[100] = 16'hFFDC;
        lut[101] = 16'hFFDE;
        lut[102] = 16'hFFDF;
        lut[103] = 16'hFFE1;
        lut[104] = 16'hFFE2;
        lut[105] = 16'hFFE4;
        lut[106] = 16'hFFE5;
        lut[107] = 16'hFFE7;
        lut[108] = 16'hFFE8;
        lut[109] = 16'hFFEA;
        lut[110] = 16'hFFEB;
        lut[111] = 16'hFFED;
        lut[112] = 16'hFFEE; // ln(0.7188)
        lut[113] = 16'hFFEF;
        lut[114] = 16'hFFF1;
        lut[115] = 16'hFFF2;
        lut[116] = 16'hFFF4;
        lut[117] = 16'hFFF5;
        lut[118] = 16'hFFF7;
        lut[119] = 16'hFFF8;
        lut[120] = 16'hFFFA;
        lut[121] = 16'hFFFB;
        lut[122] = 16'hFFFD;
        lut[123] = 16'hFFFE;
        lut[124] = 16'h0000;
        lut[125] = 16'h0001;
        lut[126] = 16'h0003;
        lut[127] = 16'h0004;
        lut[128] = 16'h0006; // ln(0.75)
        lut[129] = 16'h0007;
        lut[130] = 16'h0009;
        lut[131] = 16'h000A;
        lut[132] = 16'h000C;
        lut[133] = 16'h000D;
        lut[134] = 16'h000E;
        lut[135] = 16'h0010;
        lut[136] = 16'h0011;
        lut[137] = 16'h0013;
        lut[138] = 16'h0014;
        lut[139] = 16'h0016;
        lut[140] = 16'h0017;
        lut[141] = 16'h0018;
        lut[142] = 16'h001A;
        lut[143] = 16'h001B;
        lut[144] = 16'h001D; // ln(0.7812)
        lut[145] = 16'h001E;
        lut[146] = 16'h001F;
        lut[147] = 16'h0021;
        lut[148] = 16'h0022;
        lut[149] = 16'h0024;
        lut[150] = 16'h0025;
        lut[151] = 16'h0026;
        lut[152] = 16'h0028;
        lut[153] = 16'h0029;
        lut[154] = 16'h002B;
        lut[155] = 16'h002C;
        lut[156] = 16'h002D;
        lut[157] = 16'h002F;
        lut[158] = 16'h0030;
        lut[159] = 16'h0031;
        lut[160] = 16'h0033; // ln(0.8125)
        lut[161] = 16'h0034;
        lut[162] = 16'h0035;
        lut[163] = 16'h0037;
        lut[164] = 16'h0038;
        lut[165] = 16'h0039;
        lut[166] = 16'h003B;
        lut[167] = 16'h003C;
        lut[168] = 16'h003D;
        lut[169] = 16'h003F;
        lut[170] = 16'h0040;
        lut[171] = 16'h0041;
        lut[172] = 16'h0043;
        lut[173] = 16'h0044;
        lut[174] = 16'h0045;
        lut[175] = 16'h0047;
        lut[176] = 16'h0048; // ln(0.8438)
        lut[177] = 16'h0049;
        lut[178] = 16'h004B;
        lut[179] = 16'h004C;
        lut[180] = 16'h004D;
        lut[181] = 16'h004E;
        lut[182] = 16'h0050;
        lut[183] = 16'h0051;
        lut[184] = 16'h0052;
        lut[185] = 16'h0054;
        lut[186] = 16'h0055;
        lut[187] = 16'h0056;
        lut[188] = 16'h0057;
        lut[189] = 16'h0059;
        lut[190] = 16'h005A;
        lut[191] = 16'h005B;
        lut[192] = 16'h005D; // ln(0.875)
        lut[193] = 16'h005E;
        lut[194] = 16'h005F;
        lut[195] = 16'h0060;
        lut[196] = 16'h0062;
        lut[197] = 16'h0063;
        lut[198] = 16'h0064;
        lut[199] = 16'h0065;
        lut[200] = 16'h0067;
        lut[201] = 16'h0068;
        lut[202] = 16'h0069;
        lut[203] = 16'h006A;
        lut[204] = 16'h006C;
        lut[205] = 16'h006D;
        lut[206] = 16'h006E;
        lut[207] = 16'h006F;
        lut[208] = 16'h0071; // ln(0.9062)
        lut[209] = 16'h0072;
        lut[210] = 16'h0073;
        lut[211] = 16'h0074;
        lut[212] = 16'h0076;
        lut[213] = 16'h0077;
        lut[214] = 16'h0078;
        lut[215] = 16'h0079;
        lut[216] = 16'h007A;
        lut[217] = 16'h007C;
        lut[218] = 16'h007D;
        lut[219] = 16'h007E;
        lut[220] = 16'h007F;
        lut[221] = 16'h0080;
        lut[222] = 16'h0082;
        lut[223] = 16'h0083;
        lut[224] = 16'h0084; // ln(0.9375)
        lut[225] = 16'h0085;
        lut[226] = 16'h0086;
        lut[227] = 16'h0088;
        lut[228] = 16'h0089;
        lut[229] = 16'h008A;
        lut[230] = 16'h008B;
        lut[231] = 16'h008C;
        lut[232] = 16'h008D;
        lut[233] = 16'h008F;
        lut[234] = 16'h0090;
        lut[235] = 16'h0091;
        lut[236] = 16'h0092;
        lut[237] = 16'h0093;
        lut[238] = 16'h0094;
        lut[239] = 16'h0096;
        lut[240] = 16'h0097; // ln(0.9688)
        lut[241] = 16'h0098;
        lut[242] = 16'h0099;
        lut[243] = 16'h009A;
        lut[244] = 16'h009B;
        lut[245] = 16'h009C;
        lut[246] = 16'h009E;
        lut[247] = 16'h009F;
        lut[248] = 16'h00A0;
        lut[249] = 16'h00A1;
        lut[250] = 16'h00A2;
        lut[251] = 16'h00A3;
        lut[252] = 16'h00A4;
        lut[253] = 16'h00A5;
        lut[254] = 16'h00A7;
        lut[255] = 16'h00A8; // ln(0.9990)
    end

    always @(posedge clk) begin
        data_o <= lut[addr_i];
    end

endmodule
