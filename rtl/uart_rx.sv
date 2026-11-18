`timescale 1ns/1ps

// uart_rx.sv - UART receiver, 8N1.
// CLKS_PER_BIT = clk_freq / baud. The board design runs at 50 MHz:
//   921600 baud -> 54 (actual 925.9k, 0.47% error), 115200 baud -> 434.
// rx_valid pulses for one clock with each received byte on rx_data.
module uart_rx #(
    parameter int CLKS_PER_BIT = 54
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       rxd,        // async serial input
    output logic       rx_valid,
    output logic [7:0] rx_data
);
    localparam int CW = (CLKS_PER_BIT > 1) ? $clog2(CLKS_PER_BIT) : 1;

    // 2-flop synchronizer
    logic rxd_m, rxd_s;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rxd_m <= 1'b1;
            rxd_s <= 1'b1;
        end else begin
            rxd_m <= rxd;
            rxd_s <= rxd_m;
        end
    end

    typedef enum logic [1:0] {S_IDLE, S_START, S_DATA, S_STOP} state_t;
    state_t state;
    logic [CW-1:0] clk_cnt;
    logic [2:0]   bit_idx;
    logic [7:0]   shreg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= S_IDLE;
            clk_cnt  <= '0;
            bit_idx  <= 3'd0;
            shreg    <= 8'd0;
            rx_valid <= 1'b0;
            rx_data  <= 8'd0;
        end else begin
            rx_valid <= 1'b0;
            case (state)
                S_IDLE: begin
                    if (!rxd_s) begin
                        state   <= S_START;
                        clk_cnt <= '0;
                    end
                end

                // wait half a bit and confirm the line is still low
                S_START: begin
                    if (clk_cnt == CW'(CLKS_PER_BIT/2 - 1)) begin
                        if (!rxd_s) begin
                            state   <= S_DATA;
                            clk_cnt <= '0;
                            bit_idx <= 3'd0;
                        end else begin
                            state <= S_IDLE;   // glitch, not a start bit
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // sample each data bit at its centre, LSB first
                S_DATA: begin
                    if (clk_cnt == CW'(CLKS_PER_BIT - 1)) begin
                        clk_cnt       <= '0;
                        shreg[bit_idx] <= rxd_s;
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                // middle of the stop bit: deliver the byte
                S_STOP: begin
                    if (clk_cnt == CW'(CLKS_PER_BIT - 1)) begin
                        state    <= S_IDLE;
                        clk_cnt  <= '0;
                        rx_valid <= 1'b1;
                        rx_data  <= shreg;
                    end else begin
                        clk_cnt <= clk_cnt + 1'b1;
                    end
                end

                default: state <= S_IDLE;
            endcase
        end
    end
endmodule