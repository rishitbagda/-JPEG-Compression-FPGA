`timescale 1ns/1ps

// 2-D DCT followed by quantization. Output order is still F0,F2,F4,F6,F1,F3,F5,F7
// in both dimensions (zigzag stage goes next).
module dct_quant_top (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic [7:0]         pixel_in,

    output logic               out_valid,
    output logic signed [11:0] q_out
);
    logic               dct_valid;
    logic signed [13:0] dct_coeff;

    dct_2d_top u_dct (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .pixel_in(pixel_in),
        .out_valid(dct_valid), .dct_coeff_out(dct_coeff)
    );

    quantizer u_quant (
        .clk(clk), .rst_n(rst_n),
        .in_valid(dct_valid), .in_coeff(dct_coeff),
        .out_valid(out_valid), .out_q(q_out)
    );
endmodule
