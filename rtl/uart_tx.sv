`timescale 1ns/1ps

// uart_tx.sv - UART transmitter, 8N1.
// Pulse tx_start for one clock while tx_busy is low; the byte on tx_data is
// latched and shifted out LSB-first. tx_busy is high until the stop bit has
// been sent. Back-to-back bytes: wait for tx_busy to fall, then pulse
// tx_start again.
module uart_tx #(
    parameter int CLKS_PER_BIT = 54   // 50 MHz / 54 = 925.9 kbaud
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       tx_start,
    input  logic [7:0] tx_data,
    output logic       tx_busy,
    output logic       txd
);
    localparam int CW = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;

    logic [CW-1:0] clk_cnt;
    logic [3:0]   bit_idx;   // 0..7 = data bits, 8 = stop bit
    logic [7:0]   shreg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            txd     <= 1'b1;
            tx_busy <= 1'b0;
            clk_cnt <= '0;
            bit_idx <= 4'd0;
            shreg   <= 8'd0;
        end else if (!tx_busy) begin
            txd <= 1'b1;   // idle line
            if (tx_start) begin
                tx_busy <= 1'b1;
                shreg   <= tx_data;
                txd     <= 1'b0;   // start bit
                clk_cnt <= '0;
                bit_idx <= 4'd0;
            end
        end else begin
            if (clk_cnt == CW'(CLKS_PER_BIT - 1)) begin
                clk_cnt <= '0;
                if (bit_idx < 4'd8) begin
                    txd     <= shreg[0];
                    shreg   <= {1'b0, shreg[7:1]};
                    bit_idx <= bit_idx + 1'b1;
                end else if (bit_idx == 4'd8) begin
                    txd     <= 1'b1;   // stop bit
                    bit_idx <= 4'd9;
                end else begin
                    // stop bit has been on the line for a full bit time
                    tx_busy <= 1'b0;
                    bit_idx <= 4'd0;
                end
            end else begin
                clk_cnt <= clk_cnt + 1'b1;
            end
        end
    end
endmodule