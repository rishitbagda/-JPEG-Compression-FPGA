`timescale 1ns/1ps

// jfif_header.sv (v3) - JFIF header generator for the JPEG encoder.
// Same stream and interface as v2 (623 bytes, 156 words, MSB-first,
// 4 bytes/cycle, W/H patched into SOF0), but the byte table now comes
// from jfif_header_rom (one 156-entry word ROM) instead of four
// 623-entry per-byte case calls - the v2 hardware build zeroed byte 3
// of every beat after the first on that path.
module jfif_header #(
    parameter int IMG_W = 240,
    parameter int IMG_H = 240
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        start,
    output logic        out_valid,
    output logic [2:0]  out_nbytes,
    output logic [31:0] out_data,
    output logic        header_done
);
    localparam int NBYTES = 623;
    localparam int NWORDS = (NBYTES + 3) / 4;   // 156

    logic [15:0] word_idx;
    logic        active;

    // word 0 is emitted from the start branch (active still 0), so the ROM
    // address is 0 until active sets; then it follows word_idx.
    wire [7:0]  rom_addr = active ? word_idx[7:0] : 8'd0;
    wire [31:0] rom_word;
    jfif_header_rom u_rom (.word_idx(rom_addr), .word(rom_word));

    // SOF0 size patch, word level: bytes 163-164 = H, bytes 165-166 = W
    wire [31:0] rom_patched =
        (rom_addr == 8'd40) ? {rom_word[31:8], IMG_H[15:8]} :
        (rom_addr == 8'd41) ? {IMG_H[7:0], IMG_W[15:8], IMG_W[7:0], rom_word[7:0]} :
                              rom_word;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active      <= 1'b0;
            word_idx    <= 16'd0;
            out_valid   <= 1'b0;
            out_nbytes  <= 3'd0;
            out_data    <= 32'd0;
            header_done <= 1'b0;
        end else begin
            header_done <= 1'b0;
            if (start && !active) begin
                // start: emit word 0 immediately
                active     <= 1'b1;
                out_valid  <= 1'b1;
                out_nbytes <= (NBYTES < 4) ? 3'(NBYTES) : 3'd4;
                out_data   <= rom_patched;   // rom_addr == 0 here
                word_idx   <= 16'd1;
            end else if (active) begin
                if (word_idx < 16'(NWORDS)) begin
                    out_valid  <= 1'b1;
                    out_nbytes <= (NBYTES - word_idx*4 >= 4) ? 3'd4
                                  : 3'(NBYTES - word_idx*4);
                    out_data   <= rom_patched;
                    word_idx   <= word_idx + 16'd1;
                end else begin
                    out_valid   <= 1'b0;
                    active      <= 1'b0;
                    header_done <= 1'b1;
                end
            end else begin
                out_valid <= 1'b0;
            end
        end
    end
endmodule