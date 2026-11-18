`timescale 1ns/1ps

module transpose_buffer (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        wr_en,
    input  logic [11:0] wr_data,
    output logic        rd_valid,
    output logic [11:0] rd_data
);
    logic [11:0] ram [0:127];
    
    logic [5:0] wr_idx;
    logic       ping_pong_wr;

    logic [5:0] rd_idx;
    logic       ping_pong_rd;
    logic [1:0] blocks_ready;

    wire reading          = (blocks_ready > 2'd0);
    wire block_write_done = wr_en && (wr_idx == 6'd63);
    wire block_read_done  = reading && (rd_idx == 6'd63);

    wire [2:0] rd_col = rd_idx[5:3];
    wire [2:0] rd_row = rd_idx[2:0];

    // Memory write in its own reset-free process for BRAM inference.
    always_ff @(posedge clk) begin
        if (wr_en)
            ram[{ping_pong_wr, wr_idx}] <= wr_data;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_idx       <= 6'd0;
            ping_pong_wr <= 1'b0;
        end else if (wr_en) begin
            if (wr_idx == 6'd63) begin
                wr_idx       <= 6'd0;
                ping_pong_wr <= ~ping_pong_wr;
            end else begin
                wr_idx <= wr_idx + 6'd1;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            blocks_ready <= 2'd0;
        end else begin
            blocks_ready <= blocks_ready + block_write_done - block_read_done;
        end
    end

    // Registered read in its own reset-free process (BRAM output register);
    // rd_data is only consumed when rd_valid.
    always_ff @(posedge clk) begin
        if (reading)
            rd_data <= ram[{ping_pong_rd, rd_row, rd_col}];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_idx       <= 6'd0;
            ping_pong_rd <= 1'b0;
            rd_valid     <= 1'b0;
        end else if (reading) begin
            rd_valid <= 1'b1;
            
            if (rd_idx == 6'd63) begin
                rd_idx       <= 6'd0;
                ping_pong_rd <= ~ping_pong_rd;
            end else begin
                rd_idx <= rd_idx + 6'd1;
            end
        end else begin
            rd_valid <= 1'b0;
        end
    end
endmodule
