`timescale 1ns/1ps

module row_buffer_ping_pong #(
    parameter int W = 240
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       in_valid,
    input  logic [7:0] pixel_in,
    
    output logic       out_valid,
    output logic [7:0] pixel_out
);
    localparam int BANK_SIZE = W * 8;
    localparam int NUM_BLKS  = W / 8;

    // Dual-port BRAM holding 16 rows (2 banks of 8 rows)
    (* ram_style = "block" *) logic [7:0] ram [0:(W*16)-1];

    logic [$clog2(W)-1:0]        wr_x;
    logic [2:0]                  wr_y;
    logic                        ping_pong_wr;

    logic [$clog2(NUM_BLKS)-1:0] rd_blk_x;
    logic [2:0]                  rd_x;
    logic [2:0]                  rd_y;
    logic                        ping_pong_rd;
    logic [1:0]                  banks_ready;

    wire reading         = (banks_ready > 2'd0);
    wire bank_write_done = in_valid && (wr_x == W - 1) && (wr_y == 3'd7);
    wire bank_read_done  = reading  && (rd_x == 3'd7)  && (rd_y == 3'd7) && (rd_blk_x == NUM_BLKS - 1);

    wire [$clog2(W*16)-1:0] wr_addr = (ping_pong_wr ? BANK_SIZE : 0) + (wr_y * W) + wr_x;
    wire [$clog2(W*16)-1:0] rd_addr = (ping_pong_rd ? BANK_SIZE : 0) + (rd_y * W) + (rd_blk_x * 8) + rd_x;

    // Write Port memory. Kept in its own process with NO reset in the
    // sensitivity list so Vivado maps it to BRAM (an async reset anywhere
    // in a process that touches the array defeats BRAM inference).
    always_ff @(posedge clk) begin
        if (in_valid)
            ram[wr_addr] <= pixel_in;
    end

    // Write Port control (Raster Order)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_x         <= '0;
            wr_y         <= 3'd0;
            ping_pong_wr <= 1'b0;
        end else if (in_valid) begin
            if (wr_x == W - 1) begin
                wr_x <= '0;
                if (wr_y == 3'd7) begin
                    wr_y         <= 3'd0;
                    ping_pong_wr <= ~ping_pong_wr;
                end else begin
                    wr_y <= wr_y + 3'd1;
                end
            end else begin
                wr_x <= wr_x + 1'b1;
            end
        end
    end

    // Ping-Pong Bank Counter
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            banks_ready <= 2'd0;
        end else begin
            banks_ready <= banks_ready + bank_write_done - bank_read_done;
        end
    end

    // Read Port memory. Registered read in its own reset-free process
    // (BRAM output register); pixel_out is only consumed when out_valid.
    always_ff @(posedge clk) begin
        if (reading)
            pixel_out <= ram[rd_addr];
    end

    // Read Port control (8x8 Block Order)
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_blk_x     <= '0;
            rd_x         <= 3'd0;
            rd_y         <= 3'd0;
            ping_pong_rd <= 1'b0;
            out_valid    <= 1'b0;
        end else if (reading) begin
            out_valid <= 1'b1;
            if (rd_x == 3'd7) begin
                rd_x <= 3'd0;
                if (rd_y == 3'd7) begin
                    rd_y <= 3'd0;
                    if (rd_blk_x == NUM_BLKS - 1) begin
                        rd_blk_x     <= '0;
                        ping_pong_rd <= ~ping_pong_rd;
                    end else begin
                        rd_blk_x <= rd_blk_x + 1'b1;
                    end
                end else begin
                    rd_y <= rd_y + 3'd1;
                end
            end else begin
                rd_x <= rd_x + 3'd1;
            end
        end else begin
            out_valid <= 1'b0;
        end
    end
endmodule