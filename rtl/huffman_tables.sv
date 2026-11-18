`timescale 1ns/1ps

// Standard JPEG (ISO/IEC 10918-1 Annex K) Huffman tables, canonical codes.
// Lookup: symbol -> {code[15:0], code length[4:0]}, code left-aligned at MSB
// of the code field, i.e. the code occupies bits [15 -: clen].
//   DC symbol = SSSS (size category)   in sym[3:0]
//   AC symbol = RRRRSSSS (run<<4|size) in sym[7:0]
module huffman_tables (
    input  logic [7:0]  sym,
    output logic [15:0] dc_luma_code,
    output logic [4:0]  dc_luma_len,
    output logic [15:0] dc_chroma_code,
    output logic [4:0]  dc_chroma_len,
    output logic [15:0] ac_luma_code,
    output logic [4:0]  ac_luma_len,
    output logic [15:0] ac_chroma_code,
    output logic [4:0]  ac_chroma_len
);

    // DC_LUMA
always_comb begin
    dc_luma_code = 16'd0; dc_luma_len = 5'd0;
    case (sym)
        4'h00: begin dc_luma_code = 16'h0000; dc_luma_len = 5'd2; end
        4'h01: begin dc_luma_code = 16'h0002; dc_luma_len = 5'd3; end
        4'h02: begin dc_luma_code = 16'h0003; dc_luma_len = 5'd3; end
        4'h03: begin dc_luma_code = 16'h0004; dc_luma_len = 5'd3; end
        4'h04: begin dc_luma_code = 16'h0005; dc_luma_len = 5'd3; end
        4'h05: begin dc_luma_code = 16'h0006; dc_luma_len = 5'd3; end
        4'h06: begin dc_luma_code = 16'h000e; dc_luma_len = 5'd4; end
        4'h07: begin dc_luma_code = 16'h001e; dc_luma_len = 5'd5; end
        4'h08: begin dc_luma_code = 16'h003e; dc_luma_len = 5'd6; end
        4'h09: begin dc_luma_code = 16'h007e; dc_luma_len = 5'd7; end
        4'h0a: begin dc_luma_code = 16'h00fe; dc_luma_len = 5'd8; end
        4'h0b: begin dc_luma_code = 16'h01fe; dc_luma_len = 5'd9; end
        default: begin dc_luma_code = 16'd0; dc_luma_len = 5'd0; end
    endcase
end

    // DC_CHROMA
always_comb begin
    dc_chroma_code = 16'd0; dc_chroma_len = 5'd0;
    case (sym)
        4'h00: begin dc_chroma_code = 16'h0000; dc_chroma_len = 5'd2; end
        4'h01: begin dc_chroma_code = 16'h0001; dc_chroma_len = 5'd2; end
        4'h02: begin dc_chroma_code = 16'h0002; dc_chroma_len = 5'd2; end
        4'h03: begin dc_chroma_code = 16'h0006; dc_chroma_len = 5'd3; end
        4'h04: begin dc_chroma_code = 16'h000e; dc_chroma_len = 5'd4; end
        4'h05: begin dc_chroma_code = 16'h001e; dc_chroma_len = 5'd5; end
        4'h06: begin dc_chroma_code = 16'h003e; dc_chroma_len = 5'd6; end
        4'h07: begin dc_chroma_code = 16'h007e; dc_chroma_len = 5'd7; end
        4'h08: begin dc_chroma_code = 16'h00fe; dc_chroma_len = 5'd8; end
        4'h09: begin dc_chroma_code = 16'h01fe; dc_chroma_len = 5'd9; end
        4'h0a: begin dc_chroma_code = 16'h03fe; dc_chroma_len = 5'd10; end
        4'h0b: begin dc_chroma_code = 16'h07fe; dc_chroma_len = 5'd11; end
        default: begin dc_chroma_code = 16'd0; dc_chroma_len = 5'd0; end
    endcase
end

    // AC_LUMA
always_comb begin
    ac_luma_code = 16'd0; ac_luma_len = 5'd0;
    case (sym)
        8'h00000000: begin ac_luma_code = 16'h000a; ac_luma_len = 5'd4; end
        8'h00000001: begin ac_luma_code = 16'h0000; ac_luma_len = 5'd2; end
        8'h00000002: begin ac_luma_code = 16'h0001; ac_luma_len = 5'd2; end
        8'h00000003: begin ac_luma_code = 16'h0004; ac_luma_len = 5'd3; end
        8'h00000004: begin ac_luma_code = 16'h000b; ac_luma_len = 5'd4; end
        8'h00000005: begin ac_luma_code = 16'h001a; ac_luma_len = 5'd5; end
        8'h00000006: begin ac_luma_code = 16'h0078; ac_luma_len = 5'd7; end
        8'h00000007: begin ac_luma_code = 16'h00f8; ac_luma_len = 5'd8; end
        8'h00000008: begin ac_luma_code = 16'h03f6; ac_luma_len = 5'd10; end
        8'h00000009: begin ac_luma_code = 16'hff82; ac_luma_len = 5'd16; end
        8'h0000000a: begin ac_luma_code = 16'hff83; ac_luma_len = 5'd16; end
        8'h00000011: begin ac_luma_code = 16'h000c; ac_luma_len = 5'd4; end
        8'h00000012: begin ac_luma_code = 16'h001b; ac_luma_len = 5'd5; end
        8'h00000013: begin ac_luma_code = 16'h0079; ac_luma_len = 5'd7; end
        8'h00000014: begin ac_luma_code = 16'h01f6; ac_luma_len = 5'd9; end
        8'h00000015: begin ac_luma_code = 16'h07f6; ac_luma_len = 5'd11; end
        8'h00000016: begin ac_luma_code = 16'hff84; ac_luma_len = 5'd16; end
        8'h00000017: begin ac_luma_code = 16'hff85; ac_luma_len = 5'd16; end
        8'h00000018: begin ac_luma_code = 16'hff86; ac_luma_len = 5'd16; end
        8'h00000019: begin ac_luma_code = 16'hff87; ac_luma_len = 5'd16; end
        8'h0000001a: begin ac_luma_code = 16'hff88; ac_luma_len = 5'd16; end
        8'h00000021: begin ac_luma_code = 16'h001c; ac_luma_len = 5'd5; end
        8'h00000022: begin ac_luma_code = 16'h00f9; ac_luma_len = 5'd8; end
        8'h00000023: begin ac_luma_code = 16'h03f7; ac_luma_len = 5'd10; end
        8'h00000024: begin ac_luma_code = 16'h0ff4; ac_luma_len = 5'd12; end
        8'h00000025: begin ac_luma_code = 16'hff89; ac_luma_len = 5'd16; end
        8'h00000026: begin ac_luma_code = 16'hff8a; ac_luma_len = 5'd16; end
        8'h00000027: begin ac_luma_code = 16'hff8b; ac_luma_len = 5'd16; end
        8'h00000028: begin ac_luma_code = 16'hff8c; ac_luma_len = 5'd16; end
        8'h00000029: begin ac_luma_code = 16'hff8d; ac_luma_len = 5'd16; end
        8'h0000002a: begin ac_luma_code = 16'hff8e; ac_luma_len = 5'd16; end
        8'h00000031: begin ac_luma_code = 16'h003a; ac_luma_len = 5'd6; end
        8'h00000032: begin ac_luma_code = 16'h01f7; ac_luma_len = 5'd9; end
        8'h00000033: begin ac_luma_code = 16'h0ff5; ac_luma_len = 5'd12; end
        8'h00000034: begin ac_luma_code = 16'hff8f; ac_luma_len = 5'd16; end
        8'h00000035: begin ac_luma_code = 16'hff90; ac_luma_len = 5'd16; end
        8'h00000036: begin ac_luma_code = 16'hff91; ac_luma_len = 5'd16; end
        8'h00000037: begin ac_luma_code = 16'hff92; ac_luma_len = 5'd16; end
        8'h00000038: begin ac_luma_code = 16'hff93; ac_luma_len = 5'd16; end
        8'h00000039: begin ac_luma_code = 16'hff94; ac_luma_len = 5'd16; end
        8'h0000003a: begin ac_luma_code = 16'hff95; ac_luma_len = 5'd16; end
        8'h00000041: begin ac_luma_code = 16'h003b; ac_luma_len = 5'd6; end
        8'h00000042: begin ac_luma_code = 16'h03f8; ac_luma_len = 5'd10; end
        8'h00000043: begin ac_luma_code = 16'hff96; ac_luma_len = 5'd16; end
        8'h00000044: begin ac_luma_code = 16'hff97; ac_luma_len = 5'd16; end
        8'h00000045: begin ac_luma_code = 16'hff98; ac_luma_len = 5'd16; end
        8'h00000046: begin ac_luma_code = 16'hff99; ac_luma_len = 5'd16; end
        8'h00000047: begin ac_luma_code = 16'hff9a; ac_luma_len = 5'd16; end
        8'h00000048: begin ac_luma_code = 16'hff9b; ac_luma_len = 5'd16; end
        8'h00000049: begin ac_luma_code = 16'hff9c; ac_luma_len = 5'd16; end
        8'h0000004a: begin ac_luma_code = 16'hff9d; ac_luma_len = 5'd16; end
        8'h00000051: begin ac_luma_code = 16'h007a; ac_luma_len = 5'd7; end
        8'h00000052: begin ac_luma_code = 16'h07f7; ac_luma_len = 5'd11; end
        8'h00000053: begin ac_luma_code = 16'hff9e; ac_luma_len = 5'd16; end
        8'h00000054: begin ac_luma_code = 16'hff9f; ac_luma_len = 5'd16; end
        8'h00000055: begin ac_luma_code = 16'hffa0; ac_luma_len = 5'd16; end
        8'h00000056: begin ac_luma_code = 16'hffa1; ac_luma_len = 5'd16; end
        8'h00000057: begin ac_luma_code = 16'hffa2; ac_luma_len = 5'd16; end
        8'h00000058: begin ac_luma_code = 16'hffa3; ac_luma_len = 5'd16; end
        8'h00000059: begin ac_luma_code = 16'hffa4; ac_luma_len = 5'd16; end
        8'h0000005a: begin ac_luma_code = 16'hffa5; ac_luma_len = 5'd16; end
        8'h00000061: begin ac_luma_code = 16'h007b; ac_luma_len = 5'd7; end
        8'h00000062: begin ac_luma_code = 16'h0ff6; ac_luma_len = 5'd12; end
        8'h00000063: begin ac_luma_code = 16'hffa6; ac_luma_len = 5'd16; end
        8'h00000064: begin ac_luma_code = 16'hffa7; ac_luma_len = 5'd16; end
        8'h00000065: begin ac_luma_code = 16'hffa8; ac_luma_len = 5'd16; end
        8'h00000066: begin ac_luma_code = 16'hffa9; ac_luma_len = 5'd16; end
        8'h00000067: begin ac_luma_code = 16'hffaa; ac_luma_len = 5'd16; end
        8'h00000068: begin ac_luma_code = 16'hffab; ac_luma_len = 5'd16; end
        8'h00000069: begin ac_luma_code = 16'hffac; ac_luma_len = 5'd16; end
        8'h0000006a: begin ac_luma_code = 16'hffad; ac_luma_len = 5'd16; end
        8'h00000071: begin ac_luma_code = 16'h00fa; ac_luma_len = 5'd8; end
        8'h00000072: begin ac_luma_code = 16'h0ff7; ac_luma_len = 5'd12; end
        8'h00000073: begin ac_luma_code = 16'hffae; ac_luma_len = 5'd16; end
        8'h00000074: begin ac_luma_code = 16'hffaf; ac_luma_len = 5'd16; end
        8'h00000075: begin ac_luma_code = 16'hffb0; ac_luma_len = 5'd16; end
        8'h00000076: begin ac_luma_code = 16'hffb1; ac_luma_len = 5'd16; end
        8'h00000077: begin ac_luma_code = 16'hffb2; ac_luma_len = 5'd16; end
        8'h00000078: begin ac_luma_code = 16'hffb3; ac_luma_len = 5'd16; end
        8'h00000079: begin ac_luma_code = 16'hffb4; ac_luma_len = 5'd16; end
        8'h0000007a: begin ac_luma_code = 16'hffb5; ac_luma_len = 5'd16; end
        8'h00000081: begin ac_luma_code = 16'h01f8; ac_luma_len = 5'd9; end
        8'h00000082: begin ac_luma_code = 16'h7fc0; ac_luma_len = 5'd15; end
        8'h00000083: begin ac_luma_code = 16'hffb6; ac_luma_len = 5'd16; end
        8'h00000084: begin ac_luma_code = 16'hffb7; ac_luma_len = 5'd16; end
        8'h00000085: begin ac_luma_code = 16'hffb8; ac_luma_len = 5'd16; end
        8'h00000086: begin ac_luma_code = 16'hffb9; ac_luma_len = 5'd16; end
        8'h00000087: begin ac_luma_code = 16'hffba; ac_luma_len = 5'd16; end
        8'h00000088: begin ac_luma_code = 16'hffbb; ac_luma_len = 5'd16; end
        8'h00000089: begin ac_luma_code = 16'hffbc; ac_luma_len = 5'd16; end
        8'h0000008a: begin ac_luma_code = 16'hffbd; ac_luma_len = 5'd16; end
        8'h00000091: begin ac_luma_code = 16'h01f9; ac_luma_len = 5'd9; end
        8'h00000092: begin ac_luma_code = 16'hffbe; ac_luma_len = 5'd16; end
        8'h00000093: begin ac_luma_code = 16'hffbf; ac_luma_len = 5'd16; end
        8'h00000094: begin ac_luma_code = 16'hffc0; ac_luma_len = 5'd16; end
        8'h00000095: begin ac_luma_code = 16'hffc1; ac_luma_len = 5'd16; end
        8'h00000096: begin ac_luma_code = 16'hffc2; ac_luma_len = 5'd16; end
        8'h00000097: begin ac_luma_code = 16'hffc3; ac_luma_len = 5'd16; end
        8'h00000098: begin ac_luma_code = 16'hffc4; ac_luma_len = 5'd16; end
        8'h00000099: begin ac_luma_code = 16'hffc5; ac_luma_len = 5'd16; end
        8'h0000009a: begin ac_luma_code = 16'hffc6; ac_luma_len = 5'd16; end
        8'h000000a1: begin ac_luma_code = 16'h01fa; ac_luma_len = 5'd9; end
        8'h000000a2: begin ac_luma_code = 16'hffc7; ac_luma_len = 5'd16; end
        8'h000000a3: begin ac_luma_code = 16'hffc8; ac_luma_len = 5'd16; end
        8'h000000a4: begin ac_luma_code = 16'hffc9; ac_luma_len = 5'd16; end
        8'h000000a5: begin ac_luma_code = 16'hffca; ac_luma_len = 5'd16; end
        8'h000000a6: begin ac_luma_code = 16'hffcb; ac_luma_len = 5'd16; end
        8'h000000a7: begin ac_luma_code = 16'hffcc; ac_luma_len = 5'd16; end
        8'h000000a8: begin ac_luma_code = 16'hffcd; ac_luma_len = 5'd16; end
        8'h000000a9: begin ac_luma_code = 16'hffce; ac_luma_len = 5'd16; end
        8'h000000aa: begin ac_luma_code = 16'hffcf; ac_luma_len = 5'd16; end
        8'h000000b1: begin ac_luma_code = 16'h03f9; ac_luma_len = 5'd10; end
        8'h000000b2: begin ac_luma_code = 16'hffd0; ac_luma_len = 5'd16; end
        8'h000000b3: begin ac_luma_code = 16'hffd1; ac_luma_len = 5'd16; end
        8'h000000b4: begin ac_luma_code = 16'hffd2; ac_luma_len = 5'd16; end
        8'h000000b5: begin ac_luma_code = 16'hffd3; ac_luma_len = 5'd16; end
        8'h000000b6: begin ac_luma_code = 16'hffd4; ac_luma_len = 5'd16; end
        8'h000000b7: begin ac_luma_code = 16'hffd5; ac_luma_len = 5'd16; end
        8'h000000b8: begin ac_luma_code = 16'hffd6; ac_luma_len = 5'd16; end
        8'h000000b9: begin ac_luma_code = 16'hffd7; ac_luma_len = 5'd16; end
        8'h000000ba: begin ac_luma_code = 16'hffd8; ac_luma_len = 5'd16; end
        8'h000000c1: begin ac_luma_code = 16'h03fa; ac_luma_len = 5'd10; end
        8'h000000c2: begin ac_luma_code = 16'hffd9; ac_luma_len = 5'd16; end
        8'h000000c3: begin ac_luma_code = 16'hffda; ac_luma_len = 5'd16; end
        8'h000000c4: begin ac_luma_code = 16'hffdb; ac_luma_len = 5'd16; end
        8'h000000c5: begin ac_luma_code = 16'hffdc; ac_luma_len = 5'd16; end
        8'h000000c6: begin ac_luma_code = 16'hffdd; ac_luma_len = 5'd16; end
        8'h000000c7: begin ac_luma_code = 16'hffde; ac_luma_len = 5'd16; end
        8'h000000c8: begin ac_luma_code = 16'hffdf; ac_luma_len = 5'd16; end
        8'h000000c9: begin ac_luma_code = 16'hffe0; ac_luma_len = 5'd16; end
        8'h000000ca: begin ac_luma_code = 16'hffe1; ac_luma_len = 5'd16; end
        8'h000000d1: begin ac_luma_code = 16'h07f8; ac_luma_len = 5'd11; end
        8'h000000d2: begin ac_luma_code = 16'hffe2; ac_luma_len = 5'd16; end
        8'h000000d3: begin ac_luma_code = 16'hffe3; ac_luma_len = 5'd16; end
        8'h000000d4: begin ac_luma_code = 16'hffe4; ac_luma_len = 5'd16; end
        8'h000000d5: begin ac_luma_code = 16'hffe5; ac_luma_len = 5'd16; end
        8'h000000d6: begin ac_luma_code = 16'hffe6; ac_luma_len = 5'd16; end
        8'h000000d7: begin ac_luma_code = 16'hffe7; ac_luma_len = 5'd16; end
        8'h000000d8: begin ac_luma_code = 16'hffe8; ac_luma_len = 5'd16; end
        8'h000000d9: begin ac_luma_code = 16'hffe9; ac_luma_len = 5'd16; end
        8'h000000da: begin ac_luma_code = 16'hffea; ac_luma_len = 5'd16; end
        8'h000000e1: begin ac_luma_code = 16'hffeb; ac_luma_len = 5'd16; end
        8'h000000e2: begin ac_luma_code = 16'hffec; ac_luma_len = 5'd16; end
        8'h000000e3: begin ac_luma_code = 16'hffed; ac_luma_len = 5'd16; end
        8'h000000e4: begin ac_luma_code = 16'hffee; ac_luma_len = 5'd16; end
        8'h000000e5: begin ac_luma_code = 16'hffef; ac_luma_len = 5'd16; end
        8'h000000e6: begin ac_luma_code = 16'hfff0; ac_luma_len = 5'd16; end
        8'h000000e7: begin ac_luma_code = 16'hfff1; ac_luma_len = 5'd16; end
        8'h000000e8: begin ac_luma_code = 16'hfff2; ac_luma_len = 5'd16; end
        8'h000000e9: begin ac_luma_code = 16'hfff3; ac_luma_len = 5'd16; end
        8'h000000ea: begin ac_luma_code = 16'hfff4; ac_luma_len = 5'd16; end
        8'h000000f0: begin ac_luma_code = 16'h07f9; ac_luma_len = 5'd11; end
        8'h000000f1: begin ac_luma_code = 16'hfff5; ac_luma_len = 5'd16; end
        8'h000000f2: begin ac_luma_code = 16'hfff6; ac_luma_len = 5'd16; end
        8'h000000f3: begin ac_luma_code = 16'hfff7; ac_luma_len = 5'd16; end
        8'h000000f4: begin ac_luma_code = 16'hfff8; ac_luma_len = 5'd16; end
        8'h000000f5: begin ac_luma_code = 16'hfff9; ac_luma_len = 5'd16; end
        8'h000000f6: begin ac_luma_code = 16'hfffa; ac_luma_len = 5'd16; end
        8'h000000f7: begin ac_luma_code = 16'hfffb; ac_luma_len = 5'd16; end
        8'h000000f8: begin ac_luma_code = 16'hfffc; ac_luma_len = 5'd16; end
        8'h000000f9: begin ac_luma_code = 16'hfffd; ac_luma_len = 5'd16; end
        8'h000000fa: begin ac_luma_code = 16'hfffe; ac_luma_len = 5'd16; end
        default: begin ac_luma_code = 16'd0; ac_luma_len = 5'd0; end
    endcase
end

    // AC_CHROMA
always_comb begin
    ac_chroma_code = 16'd0; ac_chroma_len = 5'd0;
    case (sym)
        8'h00000000: begin ac_chroma_code = 16'h0000; ac_chroma_len = 5'd2; end
        8'h00000001: begin ac_chroma_code = 16'h0001; ac_chroma_len = 5'd2; end
        8'h00000002: begin ac_chroma_code = 16'h0004; ac_chroma_len = 5'd3; end
        8'h00000003: begin ac_chroma_code = 16'h000a; ac_chroma_len = 5'd4; end
        8'h00000004: begin ac_chroma_code = 16'h0018; ac_chroma_len = 5'd5; end
        8'h00000005: begin ac_chroma_code = 16'h0019; ac_chroma_len = 5'd5; end
        8'h00000006: begin ac_chroma_code = 16'h0038; ac_chroma_len = 5'd6; end
        8'h00000007: begin ac_chroma_code = 16'h0078; ac_chroma_len = 5'd7; end
        8'h00000008: begin ac_chroma_code = 16'h01f4; ac_chroma_len = 5'd9; end
        8'h00000009: begin ac_chroma_code = 16'h03f6; ac_chroma_len = 5'd10; end
        8'h0000000a: begin ac_chroma_code = 16'h0ff4; ac_chroma_len = 5'd12; end
        8'h00000011: begin ac_chroma_code = 16'h000b; ac_chroma_len = 5'd4; end
        8'h00000012: begin ac_chroma_code = 16'h0039; ac_chroma_len = 5'd6; end
        8'h00000013: begin ac_chroma_code = 16'h00f6; ac_chroma_len = 5'd8; end
        8'h00000014: begin ac_chroma_code = 16'h01f5; ac_chroma_len = 5'd9; end
        8'h00000015: begin ac_chroma_code = 16'h07f6; ac_chroma_len = 5'd11; end
        8'h00000016: begin ac_chroma_code = 16'h0ff5; ac_chroma_len = 5'd12; end
        8'h00000017: begin ac_chroma_code = 16'hff88; ac_chroma_len = 5'd16; end
        8'h00000018: begin ac_chroma_code = 16'hff89; ac_chroma_len = 5'd16; end
        8'h00000019: begin ac_chroma_code = 16'hff8a; ac_chroma_len = 5'd16; end
        8'h0000001a: begin ac_chroma_code = 16'hff8b; ac_chroma_len = 5'd16; end
        8'h00000021: begin ac_chroma_code = 16'h001a; ac_chroma_len = 5'd5; end
        8'h00000022: begin ac_chroma_code = 16'h00f7; ac_chroma_len = 5'd8; end
        8'h00000023: begin ac_chroma_code = 16'h03f7; ac_chroma_len = 5'd10; end
        8'h00000024: begin ac_chroma_code = 16'h0ff6; ac_chroma_len = 5'd12; end
        8'h00000025: begin ac_chroma_code = 16'h7fc2; ac_chroma_len = 5'd15; end
        8'h00000026: begin ac_chroma_code = 16'hff8c; ac_chroma_len = 5'd16; end
        8'h00000027: begin ac_chroma_code = 16'hff8d; ac_chroma_len = 5'd16; end
        8'h00000028: begin ac_chroma_code = 16'hff8e; ac_chroma_len = 5'd16; end
        8'h00000029: begin ac_chroma_code = 16'hff8f; ac_chroma_len = 5'd16; end
        8'h0000002a: begin ac_chroma_code = 16'hff90; ac_chroma_len = 5'd16; end
        8'h00000031: begin ac_chroma_code = 16'h001b; ac_chroma_len = 5'd5; end
        8'h00000032: begin ac_chroma_code = 16'h00f8; ac_chroma_len = 5'd8; end
        8'h00000033: begin ac_chroma_code = 16'h03f8; ac_chroma_len = 5'd10; end
        8'h00000034: begin ac_chroma_code = 16'h0ff7; ac_chroma_len = 5'd12; end
        8'h00000035: begin ac_chroma_code = 16'hff91; ac_chroma_len = 5'd16; end
        8'h00000036: begin ac_chroma_code = 16'hff92; ac_chroma_len = 5'd16; end
        8'h00000037: begin ac_chroma_code = 16'hff93; ac_chroma_len = 5'd16; end
        8'h00000038: begin ac_chroma_code = 16'hff94; ac_chroma_len = 5'd16; end
        8'h00000039: begin ac_chroma_code = 16'hff95; ac_chroma_len = 5'd16; end
        8'h0000003a: begin ac_chroma_code = 16'hff96; ac_chroma_len = 5'd16; end
        8'h00000041: begin ac_chroma_code = 16'h003a; ac_chroma_len = 5'd6; end
        8'h00000042: begin ac_chroma_code = 16'h01f6; ac_chroma_len = 5'd9; end
        8'h00000043: begin ac_chroma_code = 16'hff97; ac_chroma_len = 5'd16; end
        8'h00000044: begin ac_chroma_code = 16'hff98; ac_chroma_len = 5'd16; end
        8'h00000045: begin ac_chroma_code = 16'hff99; ac_chroma_len = 5'd16; end
        8'h00000046: begin ac_chroma_code = 16'hff9a; ac_chroma_len = 5'd16; end
        8'h00000047: begin ac_chroma_code = 16'hff9b; ac_chroma_len = 5'd16; end
        8'h00000048: begin ac_chroma_code = 16'hff9c; ac_chroma_len = 5'd16; end
        8'h00000049: begin ac_chroma_code = 16'hff9d; ac_chroma_len = 5'd16; end
        8'h0000004a: begin ac_chroma_code = 16'hff9e; ac_chroma_len = 5'd16; end
        8'h00000051: begin ac_chroma_code = 16'h003b; ac_chroma_len = 5'd6; end
        8'h00000052: begin ac_chroma_code = 16'h03f9; ac_chroma_len = 5'd10; end
        8'h00000053: begin ac_chroma_code = 16'hff9f; ac_chroma_len = 5'd16; end
        8'h00000054: begin ac_chroma_code = 16'hffa0; ac_chroma_len = 5'd16; end
        8'h00000055: begin ac_chroma_code = 16'hffa1; ac_chroma_len = 5'd16; end
        8'h00000056: begin ac_chroma_code = 16'hffa2; ac_chroma_len = 5'd16; end
        8'h00000057: begin ac_chroma_code = 16'hffa3; ac_chroma_len = 5'd16; end
        8'h00000058: begin ac_chroma_code = 16'hffa4; ac_chroma_len = 5'd16; end
        8'h00000059: begin ac_chroma_code = 16'hffa5; ac_chroma_len = 5'd16; end
        8'h0000005a: begin ac_chroma_code = 16'hffa6; ac_chroma_len = 5'd16; end
        8'h00000061: begin ac_chroma_code = 16'h0079; ac_chroma_len = 5'd7; end
        8'h00000062: begin ac_chroma_code = 16'h07f7; ac_chroma_len = 5'd11; end
        8'h00000063: begin ac_chroma_code = 16'hffa7; ac_chroma_len = 5'd16; end
        8'h00000064: begin ac_chroma_code = 16'hffa8; ac_chroma_len = 5'd16; end
        8'h00000065: begin ac_chroma_code = 16'hffa9; ac_chroma_len = 5'd16; end
        8'h00000066: begin ac_chroma_code = 16'hffaa; ac_chroma_len = 5'd16; end
        8'h00000067: begin ac_chroma_code = 16'hffab; ac_chroma_len = 5'd16; end
        8'h00000068: begin ac_chroma_code = 16'hffac; ac_chroma_len = 5'd16; end
        8'h00000069: begin ac_chroma_code = 16'hffad; ac_chroma_len = 5'd16; end
        8'h0000006a: begin ac_chroma_code = 16'hffae; ac_chroma_len = 5'd16; end
        8'h00000071: begin ac_chroma_code = 16'h007a; ac_chroma_len = 5'd7; end
        8'h00000072: begin ac_chroma_code = 16'h07f8; ac_chroma_len = 5'd11; end
        8'h00000073: begin ac_chroma_code = 16'hffaf; ac_chroma_len = 5'd16; end
        8'h00000074: begin ac_chroma_code = 16'hffb0; ac_chroma_len = 5'd16; end
        8'h00000075: begin ac_chroma_code = 16'hffb1; ac_chroma_len = 5'd16; end
        8'h00000076: begin ac_chroma_code = 16'hffb2; ac_chroma_len = 5'd16; end
        8'h00000077: begin ac_chroma_code = 16'hffb3; ac_chroma_len = 5'd16; end
        8'h00000078: begin ac_chroma_code = 16'hffb4; ac_chroma_len = 5'd16; end
        8'h00000079: begin ac_chroma_code = 16'hffb5; ac_chroma_len = 5'd16; end
        8'h0000007a: begin ac_chroma_code = 16'hffb6; ac_chroma_len = 5'd16; end
        8'h00000081: begin ac_chroma_code = 16'h00f9; ac_chroma_len = 5'd8; end
        8'h00000082: begin ac_chroma_code = 16'hffb7; ac_chroma_len = 5'd16; end
        8'h00000083: begin ac_chroma_code = 16'hffb8; ac_chroma_len = 5'd16; end
        8'h00000084: begin ac_chroma_code = 16'hffb9; ac_chroma_len = 5'd16; end
        8'h00000085: begin ac_chroma_code = 16'hffba; ac_chroma_len = 5'd16; end
        8'h00000086: begin ac_chroma_code = 16'hffbb; ac_chroma_len = 5'd16; end
        8'h00000087: begin ac_chroma_code = 16'hffbc; ac_chroma_len = 5'd16; end
        8'h00000088: begin ac_chroma_code = 16'hffbd; ac_chroma_len = 5'd16; end
        8'h00000089: begin ac_chroma_code = 16'hffbe; ac_chroma_len = 5'd16; end
        8'h0000008a: begin ac_chroma_code = 16'hffbf; ac_chroma_len = 5'd16; end
        8'h00000091: begin ac_chroma_code = 16'h01f7; ac_chroma_len = 5'd9; end
        8'h00000092: begin ac_chroma_code = 16'hffc0; ac_chroma_len = 5'd16; end
        8'h00000093: begin ac_chroma_code = 16'hffc1; ac_chroma_len = 5'd16; end
        8'h00000094: begin ac_chroma_code = 16'hffc2; ac_chroma_len = 5'd16; end
        8'h00000095: begin ac_chroma_code = 16'hffc3; ac_chroma_len = 5'd16; end
        8'h00000096: begin ac_chroma_code = 16'hffc4; ac_chroma_len = 5'd16; end
        8'h00000097: begin ac_chroma_code = 16'hffc5; ac_chroma_len = 5'd16; end
        8'h00000098: begin ac_chroma_code = 16'hffc6; ac_chroma_len = 5'd16; end
        8'h00000099: begin ac_chroma_code = 16'hffc7; ac_chroma_len = 5'd16; end
        8'h0000009a: begin ac_chroma_code = 16'hffc8; ac_chroma_len = 5'd16; end
        8'h000000a1: begin ac_chroma_code = 16'h01f8; ac_chroma_len = 5'd9; end
        8'h000000a2: begin ac_chroma_code = 16'hffc9; ac_chroma_len = 5'd16; end
        8'h000000a3: begin ac_chroma_code = 16'hffca; ac_chroma_len = 5'd16; end
        8'h000000a4: begin ac_chroma_code = 16'hffcb; ac_chroma_len = 5'd16; end
        8'h000000a5: begin ac_chroma_code = 16'hffcc; ac_chroma_len = 5'd16; end
        8'h000000a6: begin ac_chroma_code = 16'hffcd; ac_chroma_len = 5'd16; end
        8'h000000a7: begin ac_chroma_code = 16'hffce; ac_chroma_len = 5'd16; end
        8'h000000a8: begin ac_chroma_code = 16'hffcf; ac_chroma_len = 5'd16; end
        8'h000000a9: begin ac_chroma_code = 16'hffd0; ac_chroma_len = 5'd16; end
        8'h000000aa: begin ac_chroma_code = 16'hffd1; ac_chroma_len = 5'd16; end
        8'h000000b1: begin ac_chroma_code = 16'h01f9; ac_chroma_len = 5'd9; end
        8'h000000b2: begin ac_chroma_code = 16'hffd2; ac_chroma_len = 5'd16; end
        8'h000000b3: begin ac_chroma_code = 16'hffd3; ac_chroma_len = 5'd16; end
        8'h000000b4: begin ac_chroma_code = 16'hffd4; ac_chroma_len = 5'd16; end
        8'h000000b5: begin ac_chroma_code = 16'hffd5; ac_chroma_len = 5'd16; end
        8'h000000b6: begin ac_chroma_code = 16'hffd6; ac_chroma_len = 5'd16; end
        8'h000000b7: begin ac_chroma_code = 16'hffd7; ac_chroma_len = 5'd16; end
        8'h000000b8: begin ac_chroma_code = 16'hffd8; ac_chroma_len = 5'd16; end
        8'h000000b9: begin ac_chroma_code = 16'hffd9; ac_chroma_len = 5'd16; end
        8'h000000ba: begin ac_chroma_code = 16'hffda; ac_chroma_len = 5'd16; end
        8'h000000c1: begin ac_chroma_code = 16'h01fa; ac_chroma_len = 5'd9; end
        8'h000000c2: begin ac_chroma_code = 16'hffdb; ac_chroma_len = 5'd16; end
        8'h000000c3: begin ac_chroma_code = 16'hffdc; ac_chroma_len = 5'd16; end
        8'h000000c4: begin ac_chroma_code = 16'hffdd; ac_chroma_len = 5'd16; end
        8'h000000c5: begin ac_chroma_code = 16'hffde; ac_chroma_len = 5'd16; end
        8'h000000c6: begin ac_chroma_code = 16'hffdf; ac_chroma_len = 5'd16; end
        8'h000000c7: begin ac_chroma_code = 16'hffe0; ac_chroma_len = 5'd16; end
        8'h000000c8: begin ac_chroma_code = 16'hffe1; ac_chroma_len = 5'd16; end
        8'h000000c9: begin ac_chroma_code = 16'hffe2; ac_chroma_len = 5'd16; end
        8'h000000ca: begin ac_chroma_code = 16'hffe3; ac_chroma_len = 5'd16; end
        8'h000000d1: begin ac_chroma_code = 16'h07f9; ac_chroma_len = 5'd11; end
        8'h000000d2: begin ac_chroma_code = 16'hffe4; ac_chroma_len = 5'd16; end
        8'h000000d3: begin ac_chroma_code = 16'hffe5; ac_chroma_len = 5'd16; end
        8'h000000d4: begin ac_chroma_code = 16'hffe6; ac_chroma_len = 5'd16; end
        8'h000000d5: begin ac_chroma_code = 16'hffe7; ac_chroma_len = 5'd16; end
        8'h000000d6: begin ac_chroma_code = 16'hffe8; ac_chroma_len = 5'd16; end
        8'h000000d7: begin ac_chroma_code = 16'hffe9; ac_chroma_len = 5'd16; end
        8'h000000d8: begin ac_chroma_code = 16'hffea; ac_chroma_len = 5'd16; end
        8'h000000d9: begin ac_chroma_code = 16'hffeb; ac_chroma_len = 5'd16; end
        8'h000000da: begin ac_chroma_code = 16'hffec; ac_chroma_len = 5'd16; end
        8'h000000e1: begin ac_chroma_code = 16'h3fe0; ac_chroma_len = 5'd14; end
        8'h000000e2: begin ac_chroma_code = 16'hffed; ac_chroma_len = 5'd16; end
        8'h000000e3: begin ac_chroma_code = 16'hffee; ac_chroma_len = 5'd16; end
        8'h000000e4: begin ac_chroma_code = 16'hffef; ac_chroma_len = 5'd16; end
        8'h000000e5: begin ac_chroma_code = 16'hfff0; ac_chroma_len = 5'd16; end
        8'h000000e6: begin ac_chroma_code = 16'hfff1; ac_chroma_len = 5'd16; end
        8'h000000e7: begin ac_chroma_code = 16'hfff2; ac_chroma_len = 5'd16; end
        8'h000000e8: begin ac_chroma_code = 16'hfff3; ac_chroma_len = 5'd16; end
        8'h000000e9: begin ac_chroma_code = 16'hfff4; ac_chroma_len = 5'd16; end
        8'h000000ea: begin ac_chroma_code = 16'hfff5; ac_chroma_len = 5'd16; end
        8'h000000f0: begin ac_chroma_code = 16'h03fa; ac_chroma_len = 5'd10; end
        8'h000000f1: begin ac_chroma_code = 16'h7fc3; ac_chroma_len = 5'd15; end
        8'h000000f2: begin ac_chroma_code = 16'hfff6; ac_chroma_len = 5'd16; end
        8'h000000f3: begin ac_chroma_code = 16'hfff7; ac_chroma_len = 5'd16; end
        8'h000000f4: begin ac_chroma_code = 16'hfff8; ac_chroma_len = 5'd16; end
        8'h000000f5: begin ac_chroma_code = 16'hfff9; ac_chroma_len = 5'd16; end
        8'h000000f6: begin ac_chroma_code = 16'hfffa; ac_chroma_len = 5'd16; end
        8'h000000f7: begin ac_chroma_code = 16'hfffb; ac_chroma_len = 5'd16; end
        8'h000000f8: begin ac_chroma_code = 16'hfffc; ac_chroma_len = 5'd16; end
        8'h000000f9: begin ac_chroma_code = 16'hfffd; ac_chroma_len = 5'd16; end
        8'h000000fa: begin ac_chroma_code = 16'hfffe; ac_chroma_len = 5'd16; end
        default: begin ac_chroma_code = 16'd0; ac_chroma_len = 5'd0; end
    endcase
end

endmodule
