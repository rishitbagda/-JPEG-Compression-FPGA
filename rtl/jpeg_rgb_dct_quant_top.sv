`timescale 1ns/1ps

// jpeg_rgb_dct_top + per-channel quantizers.
//   RGB -> YCbCr -> 16-row buffers -> 2D DCT -> quantizer (Y: luma table, Cb/Cr: chroma table)
// Output order of every channel: F0,F2,F4,F6,F1,F3,F5,F7 in both dimensions
// (zigzag stage goes next).
module jpeg_rgb_dct_quant_top #(
    parameter int W = 240,
    parameter int H = 240
) (
    input  logic               clk,
    input  logic               rst_n,

    // Streaming RGB camera/ROM input (raster scan)
    input  logic               in_valid,
    input  logic [7:0]         r, g, b,

    // 3-channel quantized coefficient streams
    output logic               q_valid_y,
    output logic signed [11:0] q_y,

    output logic               q_valid_cb,
    output logic signed [11:0] q_cb,

    output logic               q_valid_cr,
    output logic signed [11:0] q_cr
);
    // ---------------------------------------------------------------- Stage 1
    logic       ycbcr_valid;
    logic [7:0] y_pix, cb_pix, cr_pix;

    rgb_to_ycbcr u_rgb2ycbcr (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .r(r), .g(g), .b(b),
        .out_valid(ycbcr_valid), .y(y_pix), .cb(cb_pix), .cr(cr_pix)
    );

    // ---------------------------------------------------------------- Stage 2
    logic       blk_valid_y,  blk_valid_cb,  blk_valid_cr;
    logic [7:0] blk_pixel_y,  blk_pixel_cb,  blk_pixel_cr;

    row_buffer_ping_pong #(.W(W)) u_row_buf_y (
        .clk(clk), .rst_n(rst_n),
        .in_valid(ycbcr_valid), .pixel_in(y_pix),
        .out_valid(blk_valid_y), .pixel_out(blk_pixel_y)
    );
    row_buffer_ping_pong #(.W(W)) u_row_buf_cb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(ycbcr_valid), .pixel_in(cb_pix),
        .out_valid(blk_valid_cb), .pixel_out(blk_pixel_cb)
    );
    row_buffer_ping_pong #(.W(W)) u_row_buf_cr (
        .clk(clk), .rst_n(rst_n),
        .in_valid(ycbcr_valid), .pixel_in(cr_pix),
        .out_valid(blk_valid_cr), .pixel_out(blk_pixel_cr)
    );

    // ---------------------------------------------------------------- Stage 3
    logic               dct_valid_y,  dct_valid_cb,  dct_valid_cr;
    logic signed [13:0] dct_y,        dct_cb,        dct_cr;

    dct_2d_top u_dct_2d_y (
        .clk(clk), .rst_n(rst_n),
        .in_valid(blk_valid_y), .pixel_in(blk_pixel_y),
        .out_valid(dct_valid_y), .dct_coeff_out(dct_y)
    );
    dct_2d_top u_dct_2d_cb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(blk_valid_cb), .pixel_in(blk_pixel_cb),
        .out_valid(dct_valid_cb), .dct_coeff_out(dct_cb)
    );
    dct_2d_top u_dct_2d_cr (
        .clk(clk), .rst_n(rst_n),
        .in_valid(blk_valid_cr), .pixel_in(blk_pixel_cr),
        .out_valid(dct_valid_cr), .dct_coeff_out(dct_cr)
    );

    // ---------------------------------------------------------------- Stage 4
    quantizer #(.IS_CHROMA(1'b0)) u_quant_y (
        .clk(clk), .rst_n(rst_n),
        .in_valid(dct_valid_y), .in_coeff(dct_y),
        .out_valid(q_valid_y), .out_q(q_y)
    );
    quantizer #(.IS_CHROMA(1'b1)) u_quant_cb (
        .clk(clk), .rst_n(rst_n),
        .in_valid(dct_valid_cb), .in_coeff(dct_cb),
        .out_valid(q_valid_cb), .out_q(q_cb)
    );
    quantizer #(.IS_CHROMA(1'b1)) u_quant_cr (
        .clk(clk), .rst_n(rst_n),
        .in_valid(dct_valid_cr), .in_coeff(dct_cr),
        .out_valid(q_valid_cr), .out_q(q_cr)
    );
endmodule
