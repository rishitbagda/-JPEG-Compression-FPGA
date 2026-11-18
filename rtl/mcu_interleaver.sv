`timescale 1ns/1ps

// MCU interleaver: merges the Y, Cb, Cr token streams into the single
// entropy-coding order Y,Cb,Cr per MCU (4:4:4, one 8x8 block per component).
// Each channel's tokens are buffered in a FWFT FIFO; every block ends with
// exactly one token marked "last". After the final block of the final MCU,
// out_flush pulses once with the last token.
//
// fifo_full_err is a sticky error flag: it means a FIFO overflowed, which
// requires sustained token rates above 1 token/cycle (pathological image
// content). Watch fifo_count to throttle the pixel source if needed.
module mcu_interleaver #(
    parameter int NBLOCKS = 900        // MCUs = (W/8)*(H/8)
) (
    input  logic        clk,
    input  logic        rst_n,

    input  logic        in_valid_y,
    input  logic        in_last_y,
    input  logic        in_is_dc_y,
    input  logic [3:0]  in_run_y,
    input  logic [3:0]  in_size_y,
    input  logic [10:0] in_amp_y,

    input  logic        in_valid_cb,
    input  logic        in_last_cb,
    input  logic        in_is_dc_cb,
    input  logic [3:0]  in_run_cb,
    input  logic [3:0]  in_size_cb,
    input  logic [10:0] in_amp_cb,

    input  logic        in_valid_cr,
    input  logic        in_last_cr,
    input  logic        in_is_dc_cr,
    input  logic [3:0]  in_run_cr,
    input  logic [3:0]  in_size_cr,
    input  logic [10:0] in_amp_cr,

    output logic        out_valid,
    output logic        out_flush,
    output logic        out_is_dc,
    output logic [3:0]  out_run,
    output logic [3:0]  out_size,
    output logic [10:0] out_amp,
    output logic [1:0]  out_comp,

    output logic        fifo_full_err,
    output logic [8:0]  fifo_count_y,
    output logic [8:0]  fifo_count_cb,
    output logic [8:0]  fifo_count_cr
);
    localparam int DW = 20;  // {is_dc, run, size, amp}

    logic         rd_y, rd_cb, rd_cr;
    logic [DW:0]  fifo_din_y, fifo_din_cb, fifo_din_cr;   // {last, token}
    logic [DW:0]  fifo_dout_y, fifo_dout_cb, fifo_dout_cr;
    logic         empty_y, empty_cb, empty_cr, full_y, full_cb, full_cr;

    assign fifo_din_y  = {in_last_y,  in_is_dc_y,  in_run_y,  in_size_y,  in_amp_y};
    assign fifo_din_cb = {in_last_cb, in_is_dc_cb, in_run_cb, in_size_cb, in_amp_cb};
    assign fifo_din_cr = {in_last_cr, in_is_dc_cr, in_run_cr, in_size_cr, in_amp_cr};

    token_fifo #(.DW(DW+1), .AW(8)) u_fifo_y (
        .clk(clk), .rst_n(rst_n),
        .wr_en(in_valid_y),  .wr_data(fifo_din_y),  .full(full_y),  .count(fifo_count_y),
        .rd_en(rd_y),  .rd_data(fifo_dout_y),  .empty(empty_y)
    );
    token_fifo #(.DW(DW+1), .AW(8)) u_fifo_cb (
        .clk(clk), .rst_n(rst_n),
        .wr_en(in_valid_cb), .wr_data(fifo_din_cb), .full(full_cb), .count(fifo_count_cb),
        .rd_en(rd_cb), .rd_data(fifo_dout_cb), .empty(empty_cb)
    );
    token_fifo #(.DW(DW+1), .AW(8)) u_fifo_cr (
        .clk(clk), .rst_n(rst_n),
        .wr_en(in_valid_cr), .wr_data(fifo_din_cr), .full(full_cr), .count(fifo_count_cr),
        .rd_en(rd_cr), .rd_data(fifo_dout_cr), .empty(empty_cr)
    );

    // sticky overflow flag
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            fifo_full_err <= 1'b0;
        else if ((in_valid_y && full_y) || (in_valid_cb && full_cb) || (in_valid_cr && full_cr))
            fifo_full_err <= 1'b1;
    end

    // drain FSM: Y block -> Cb block -> Cr block, repeat; flush after last MCU
    typedef enum logic [1:0] {S_Y, S_CB, S_CR} state_t;
    state_t      state;
    logic [31:0] mcu_cnt;

    wire        cur_empty = (state == S_Y) ? empty_y : (state == S_CB) ? empty_cb : empty_cr;
    wire [DW:0] cur_dout  = (state == S_Y) ? fifo_dout_y : (state == S_CB) ? fifo_dout_cb : fifo_dout_cr;

    assign rd_y  = (state == S_Y)  && !cur_empty;
    assign rd_cb = (state == S_CB) && !cur_empty;
    assign rd_cr = (state == S_CR) && !cur_empty;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_Y;
            mcu_cnt   <= 32'd0;
            out_valid <= 1'b0;
            out_flush <= 1'b0;
            out_is_dc <= 1'b0;
            out_run   <= 4'd0;
            out_size  <= 4'd0;
            out_amp   <= 11'd0;
            out_comp  <= 2'd0;
        end else begin
            out_valid <= 1'b0;
            out_flush <= 1'b0;
            if (!cur_empty) begin
                out_valid <= 1'b1;
                out_comp  <= (state == S_Y) ? 2'd0 : (state == S_CB) ? 2'd1 : 2'd2;
                out_is_dc <= cur_dout[19];
                out_run   <= cur_dout[18:15];
                out_size  <= cur_dout[14:11];
                out_amp   <= cur_dout[10:0];
                if (cur_dout[20]) begin  // block finished -> next component
                    if (state == S_CR) begin
                        state <= S_Y;
                        if (mcu_cnt == 32'(NBLOCKS - 1)) begin
                            out_flush <= 1'b1;   // whole scan encoded
                            mcu_cnt   <= mcu_cnt; // hold
                        end else begin
                            mcu_cnt <= mcu_cnt + 32'd1;
                        end
                    end else begin
                        state <= (state == S_Y) ? S_CB : S_CR;
                    end
                end
            end
        end
    end
endmodule
