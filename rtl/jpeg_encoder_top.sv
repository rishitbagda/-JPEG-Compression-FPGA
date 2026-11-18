`timescale 1ns/1ps

// Complete JPEG encoder: RGB pixels in -> JPEG scan byte stream out.
// Front end (existing): rgb_to_ycbcr -> row buffers -> 2D DCT -> quantizers.
// Back end (new):       jpeg_scan_top (zigzag, RLE, Huffman, bit packing).
//
// W and H must be multiples of 8. Feed W*H pixels in raster order with
// in_valid. The scan byte stream comes out on out_data (out_nbytes bytes,
// MSB first); scan_done pulses after the final byte. Assemble the .jpg
// file off-chip with assemble_jpeg.py.
module jpeg_encoder_top #(
    parameter int W = 240,
    parameter int H = 240
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [7:0]  r, g, b,

    output logic        out_valid,
    output logic [2:0]  out_nbytes,
    output logic [31:0] out_data,
    output logic        scan_done,
    output logic        fifo_full_err
);
    logic               q_valid_y, q_valid_cb, q_valid_cr;
    logic signed [11:0] q_y, q_cb, q_cr;

    jpeg_rgb_dct_quant_top #(.W(W), .H(H)) u_front (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .r(r), .g(g), .b(b),
        .q_valid_y(q_valid_y),   .q_y(q_y),
        .q_valid_cb(q_valid_cb), .q_cb(q_cb),
        .q_valid_cr(q_valid_cr), .q_cr(q_cr)
    );

    jpeg_scan_top #(.W(W), .H(H)) u_scan (
        .clk(clk), .rst_n(rst_n),
        .q_valid_y(q_valid_y),   .q_y(q_y),
        .q_valid_cb(q_valid_cb), .q_cb(q_cb),
        .q_valid_cr(q_valid_cr), .q_cr(q_cr),
        .out_valid(out_valid), .out_nbytes(out_nbytes),
        .out_data(out_data),   .scan_done(scan_done),
        .fifo_full_err(fifo_full_err),
        .fifo_count_y(), .fifo_count_cb(), .fifo_count_cr()
    );
endmodule
