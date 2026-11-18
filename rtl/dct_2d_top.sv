`timescale 1ns/1ps

module dct_2d_top (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic [7:0]         pixel_in,
    
    output logic               out_valid,
    output logic signed [13:0] dct_coeff_out
);
    logic               row_out_valid;
    logic signed [13:0] row_out_data;
    
    logic               transpose_valid;
    logic [11:0]        transpose_data;

    dct_1d #(
        .IS_ROW_PASS(1)
    ) u_row_dct (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .in_data   ({4'b0000, pixel_in}),
        .out_valid (row_out_valid),
        .out_data  (row_out_data)
    );

    transpose_buffer u_trans_buf (
        .clk       (clk),
        .rst_n     (rst_n),
        .wr_en     (row_out_valid),
        .wr_data   (row_out_data[11:0]),
        .rd_valid  (transpose_valid),
        .rd_data   (transpose_data)
    );

    dct_1d #(
        .IS_ROW_PASS(0)
    ) u_col_dct (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (transpose_valid),
        .in_data   (transpose_data),
        .out_valid (out_valid),
        .out_data  (dct_coeff_out)
    );
endmodule