`timescale 1ns/1ps

// Entropy-coding back end of the JPEG encoder. Plugs directly into
// jpeg_rgb_dct_quant_top: takes the three quantized coefficient streams
// (DCT stream order, 64 coefficients per 8x8 block) and produces the
// JPEG scan byte stream (byte-stuffed, 1s-padded at the end).
//
// Chain: zigzag_reorder x3 -> rle_encode x3 -> mcu_interleaver
//        -> huffman_encode (Annex K tables) -> bit_packer.
//
// NBLOCKS must equal (W/8)*(H/8); W and H must be multiples of 8
// (pad the image beforehand otherwise).
//
// The output is the raw entropy-coded segment only: the JFIF headers
// (SOI/APP0/DQT/SOF0/DHT/SOS) and the EOI marker are added off-chip by
// assemble_jpeg.py. out_data carries out_nbytes bytes, MSB first.
module jpeg_scan_top #(
    parameter int W = 240,
    parameter int H = 240
) (
    input  logic               clk,
    input  logic               rst_n,

    input  logic               q_valid_y,
    input  logic signed [11:0] q_y,
    input  logic               q_valid_cb,
    input  logic signed [11:0] q_cb,
    input  logic               q_valid_cr,
    input  logic signed [11:0] q_cr,

    output logic               out_valid,
    output logic [2:0]         out_nbytes,
    output logic [31:0]        out_data,
    output logic               scan_done,

    output logic               fifo_full_err,
    output logic [8:0]         fifo_count_y,
    output logic [8:0]         fifo_count_cb,
    output logic [8:0]         fifo_count_cr
);
    localparam int NBLOCKS = (W / 8) * (H / 8);

    // ---------------- zigzag reorder x3 ----------------
    logic               zz_valid_y, zz_valid_cb, zz_valid_cr;
    logic signed [11:0] zz_y, zz_cb, zz_cr;

    zigzag_reorder u_zigzag_y (
        .clk(clk), .rst_n(rst_n),
        .in_valid(q_valid_y), .in_coeff(q_y),
        .out_valid(zz_valid_y), .out_coeff(zz_y)
    );
    zigzag_reorder u_zigzag_cb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(q_valid_cb), .in_coeff(q_cb),
        .out_valid(zz_valid_cb), .out_coeff(zz_cb)
    );
    zigzag_reorder u_zigzag_cr (
        .clk(clk), .rst_n(rst_n),
        .in_valid(q_valid_cr), .in_coeff(q_cr),
        .out_valid(zz_valid_cr), .out_coeff(zz_cr)
    );

    // ---------------- run-length encoding x3 ----------------
    logic        rle_valid_y, rle_valid_cb, rle_valid_cr;
    logic        rle_last_y,  rle_last_cb,  rle_last_cr;
    logic        rle_is_dc_y, rle_is_dc_cb, rle_is_dc_cr;
    logic [3:0]  rle_run_y,   rle_run_cb,   rle_run_cr;
    logic [3:0]  rle_size_y,  rle_size_cb,  rle_size_cr;
    logic [10:0] rle_amp_y,   rle_amp_cb,   rle_amp_cr;

    rle_encode u_rle_y (
        .clk(clk), .rst_n(rst_n),
        .in_valid(zz_valid_y), .in_coeff(zz_y),
        .out_valid(rle_valid_y), .out_last(rle_last_y),
        .out_is_dc(rle_is_dc_y), .out_run(rle_run_y),
        .out_size(rle_size_y), .out_amp(rle_amp_y)
    );
    rle_encode u_rle_cb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(zz_valid_cb), .in_coeff(zz_cb),
        .out_valid(rle_valid_cb), .out_last(rle_last_cb),
        .out_is_dc(rle_is_dc_cb), .out_run(rle_run_cb),
        .out_size(rle_size_cb), .out_amp(rle_amp_cb)
    );
    rle_encode u_rle_cr (
        .clk(clk), .rst_n(rst_n),
        .in_valid(zz_valid_cr), .in_coeff(zz_cr),
        .out_valid(rle_valid_cr), .out_last(rle_last_cr),
        .out_is_dc(rle_is_dc_cr), .out_run(rle_run_cr),
        .out_size(rle_size_cr), .out_amp(rle_amp_cr)
    );

    // ---------------- MCU interleave -> Huffman -> pack ----------------
    logic        h_valid, h_flush, h_is_dc;
    logic [3:0]  h_run, h_size;
    logic [10:0] h_amp;
    logic [1:0]  h_comp;

    mcu_interleaver #(.NBLOCKS(NBLOCKS)) u_interleaver (
        .clk(clk), .rst_n(rst_n),
        .in_valid_y(rle_valid_y),  .in_last_y(rle_last_y),
        .in_is_dc_y(rle_is_dc_y),  .in_run_y(rle_run_y),
        .in_size_y(rle_size_y),    .in_amp_y(rle_amp_y),
        .in_valid_cb(rle_valid_cb), .in_last_cb(rle_last_cb),
        .in_is_dc_cb(rle_is_dc_cb), .in_run_cb(rle_run_cb),
        .in_size_cb(rle_size_cb),   .in_amp_cb(rle_amp_cb),
        .in_valid_cr(rle_valid_cr), .in_last_cr(rle_last_cr),
        .in_is_dc_cr(rle_is_dc_cr), .in_run_cr(rle_run_cr),
        .in_size_cr(rle_size_cr),   .in_amp_cr(rle_amp_cr),
        .out_valid(h_valid), .out_flush(h_flush),
        .out_is_dc(h_is_dc), .out_run(h_run),
        .out_size(h_size),   .out_amp(h_amp),
        .out_comp(h_comp),
        .fifo_full_err(fifo_full_err),
        .fifo_count_y(fifo_count_y),
        .fifo_count_cb(fifo_count_cb),
        .fifo_count_cr(fifo_count_cr)
    );

    logic        e_valid, e_flush;
    logic [26:0] e_bits;
    logic [5:0]  e_nbits;

    huffman_encode u_huffman (
        .clk(clk), .rst_n(rst_n),
        .in_valid(h_valid), .in_flush(h_flush),
        .in_is_dc(h_is_dc), .in_run(h_run),
        .in_size(h_size),   .in_amp(h_amp),
        .in_comp(h_comp),
        .out_valid(e_valid), .out_flush(e_flush),
        .out_bits(e_bits),   .out_nbits(e_nbits)
    );

    bit_packer u_packer (
        .clk(clk), .rst_n(rst_n),
        .in_valid(e_valid), .in_flush(e_flush),
        .in_bits(e_bits),   .in_nbits(e_nbits),
        .out_valid(out_valid), .out_nbytes(out_nbytes),
        .out_data(out_data),   .out_done(scan_done)
    );
endmodule
