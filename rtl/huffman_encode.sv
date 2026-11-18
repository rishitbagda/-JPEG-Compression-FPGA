`timescale 1ns/1ps

// Huffman encoding: one RLE token per cycle -> variable-length bit segment.
//   DC token: symbol = SSSS,          code from DC luma/chroma table + size amplitude bits
//   AC token: symbol = (RRRR,SSSS),   code from AC luma/chroma table + size amplitude bits
//   EOB (0,0) and ZRL (15,0) have size 0 -> code only, no amplitude bits.
// in_comp: 0 = Y (luma tables), 1/2 = Cb/Cr (chroma tables).
// in_flush is carried with the last token of the scan and tells the bit
// packer to pad out the final byte after this token.
module huffman_encode (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic        in_flush,
    input  logic        in_is_dc,
    input  logic [3:0]  in_run,
    input  logic [3:0]  in_size,
    input  logic [10:0] in_amp,
    input  logic [1:0]  in_comp,
    output logic        out_valid,
    output logic        out_flush,
    output logic [26:0] out_bits,
    output logic [5:0]  out_nbits
);
    logic [7:0]  sym;
    logic [15:0] dc_luma_code, dc_chroma_code, ac_luma_code, ac_chroma_code;
    logic [4:0]  dc_luma_len, dc_chroma_len, ac_luma_len, ac_chroma_len;

    assign sym = in_is_dc ? {4'd0, in_size} : {in_run, in_size};

    huffman_tables u_tables (
        .sym            (sym),
        .dc_luma_code   (dc_luma_code),
        .dc_luma_len   (dc_luma_len),
        .dc_chroma_code (dc_chroma_code),
        .dc_chroma_len (dc_chroma_len),
        .ac_luma_code   (ac_luma_code),
        .ac_luma_len   (ac_luma_len),
        .ac_chroma_code (ac_chroma_code),
        .ac_chroma_len (ac_chroma_len)
    );

    logic [15:0] code;
    logic [4:0]  clen;
    always_comb begin
        if (in_is_dc) begin
            code = (in_comp == 2'd0) ? dc_luma_code : dc_chroma_code;
            clen = (in_comp == 2'd0) ? dc_luma_len : dc_chroma_len;
        end else begin
            code = (in_comp == 2'd0) ? ac_luma_code : ac_chroma_code;
            clen = (in_comp == 2'd0) ? ac_luma_len : ac_chroma_len;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_flush <= 1'b0;
            out_bits  <= 27'd0;
            out_nbits <= 6'd0;
        end else begin
            out_valid <= in_valid;
            out_flush <= in_valid && in_flush;
            if (in_valid) begin
                // code left-aligned in [26:11], amplitude appended below it
                out_bits  <= ({11'd0, code} << in_size) | 27'(in_amp);
                out_nbits <= {1'b0, clen} + {2'd0, in_size};
            end
        end
    end
endmodule
