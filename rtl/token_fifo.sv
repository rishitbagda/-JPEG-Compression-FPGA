`timescale 1ns/1ps

// First-word-fall-through FIFO (distributed RAM, asynchronous read).
module token_fifo #(
    parameter int DW = 21,
    parameter int AW = 8               // depth = 2**AW
) (
    input  logic           clk,
    input  logic           rst_n,
    input  logic           wr_en,
    input  logic [DW-1:0]  wr_data,
    output logic           full,
    output logic [AW:0]    count,
    input  logic           rd_en,
    output logic [DW-1:0]  rd_data,
    output logic           empty
);
    (* ram_style = "distributed" *) logic [DW-1:0] mem [0:(1<<AW)-1];
    logic [AW-1:0] wptr, rptr;
    logic [AW:0]   cnt;

    assign full    = (cnt == (AW+1)'(1 << AW));
    assign empty   = (cnt == '0);
    assign count   = cnt;
    assign rd_data = mem[rptr];

    // Memory write in its own reset-free process so Vivado infers
    // distributed RAM (an async reset in the writing process forces FFs).
    always_ff @(posedge clk) begin
        if (wr_en && !full)
            mem[wptr] <= wr_data;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wptr <= '0;
            rptr <= '0;
            cnt  <= '0;
        end else begin
            if (wr_en && !full) begin
                wptr      <= wptr + 1'b1;
            end
            if (rd_en && !empty) begin
                rptr <= rptr + 1'b1;
            end
            cnt <= cnt + ((wr_en && !full) ? 1'b1 : 1'b0) - ((rd_en && !empty) ? 1'b1 : 1'b0);
        end
    end
endmodule
