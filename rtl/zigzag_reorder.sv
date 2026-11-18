`timescale 1ns/1ps

// Zigzag reorder: one 8x8 block per channel, streamed.
// Input  : quantized coefficients in DCT stream order
//          (idx = g*8+k, u = ORDER[g], v = ORDER[k], ORDER = 0,2,4,6,1,3,5,7)
// Output : the same block in true JPEG zigzag scan order (DC first).
// Ping-pong block buffer, same structure as transpose_buffer.
module zigzag_reorder (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic signed [11:0] in_coeff,
    output logic               out_valid,
    output logic signed [11:0] out_coeff
);
    logic signed [11:0] ram [0:127];

    logic [5:0] wr_idx;
    logic       ping_pong_wr;

    logic [5:0] rd_idx;
    logic       ping_pong_rd;
    logic [1:0] blocks_ready;

    wire reading          = (blocks_ready > 2'd0);
    wire block_write_done = in_valid && (wr_idx == 6'd63);
    wire block_read_done  = reading && (rd_idx == 6'd63);

    // zigzag scan position -> stream-order RAM address
    logic [5:0] zz_addr;
    always_comb begin
        case (rd_idx)
            6'd 0: zz_addr = 6'd0;
            6'd 1: zz_addr = 6'd32;
            6'd 2: zz_addr = 6'd4;
            6'd 3: zz_addr = 6'd1;
            6'd 4: zz_addr = 6'd36;
            6'd 5: zz_addr = 6'd8;
            6'd 6: zz_addr = 6'd40;
            6'd 7: zz_addr = 6'd12;
            6'd 8: zz_addr = 6'd33;
            6'd 9: zz_addr = 6'd5;
            6'd10: zz_addr = 6'd2;
            6'd11: zz_addr = 6'd37;
            6'd12: zz_addr = 6'd9;
            6'd13: zz_addr = 6'd44;
            6'd14: zz_addr = 6'd16;
            6'd15: zz_addr = 6'd48;
            6'd16: zz_addr = 6'd20;
            6'd17: zz_addr = 6'd41;
            6'd18: zz_addr = 6'd13;
            6'd19: zz_addr = 6'd34;
            6'd20: zz_addr = 6'd6;
            6'd21: zz_addr = 6'd3;
            6'd22: zz_addr = 6'd38;
            6'd23: zz_addr = 6'd10;
            6'd24: zz_addr = 6'd45;
            6'd25: zz_addr = 6'd17;
            6'd26: zz_addr = 6'd52;
            6'd27: zz_addr = 6'd24;
            6'd28: zz_addr = 6'd56;
            6'd29: zz_addr = 6'd28;
            6'd30: zz_addr = 6'd49;
            6'd31: zz_addr = 6'd21;
            6'd32: zz_addr = 6'd42;
            6'd33: zz_addr = 6'd14;
            6'd34: zz_addr = 6'd35;
            6'd35: zz_addr = 6'd7;
            6'd36: zz_addr = 6'd39;
            6'd37: zz_addr = 6'd11;
            6'd38: zz_addr = 6'd46;
            6'd39: zz_addr = 6'd18;
            6'd40: zz_addr = 6'd53;
            6'd41: zz_addr = 6'd25;
            6'd42: zz_addr = 6'd60;
            6'd43: zz_addr = 6'd57;
            6'd44: zz_addr = 6'd29;
            6'd45: zz_addr = 6'd50;
            6'd46: zz_addr = 6'd22;
            6'd47: zz_addr = 6'd43;
            6'd48: zz_addr = 6'd15;
            6'd49: zz_addr = 6'd47;
            6'd50: zz_addr = 6'd19;
            6'd51: zz_addr = 6'd54;
            6'd52: zz_addr = 6'd26;
            6'd53: zz_addr = 6'd61;
            6'd54: zz_addr = 6'd58;
            6'd55: zz_addr = 6'd30;
            6'd56: zz_addr = 6'd51;
            6'd57: zz_addr = 6'd23;
            6'd58: zz_addr = 6'd55;
            6'd59: zz_addr = 6'd27;
            6'd60: zz_addr = 6'd62;
            6'd61: zz_addr = 6'd59;
            6'd62: zz_addr = 6'd31;
            6'd63: zz_addr = 6'd63;
            default: zz_addr = 6'd0;
        endcase
    end

    // Memory write in its own reset-free process for BRAM inference.
    always_ff @(posedge clk) begin
        if (in_valid)
            ram[{ping_pong_wr, wr_idx}] <= in_coeff;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_idx       <= 6'd0;
            ping_pong_wr <= 1'b0;
        end else if (in_valid) begin
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
    // out_coeff is only consumed when out_valid.
    always_ff @(posedge clk) begin
        if (reading)
            out_coeff <= ram[{ping_pong_rd, zz_addr}];
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_idx       <= 6'd0;
            ping_pong_rd <= 1'b0;
            out_valid    <= 1'b0;
        end else if (reading) begin
            out_valid <= 1'b1;
            if (rd_idx == 6'd63) begin
                rd_idx       <= 6'd0;
                ping_pong_rd <= ~ping_pong_rd;
            end else begin
                rd_idx <= rd_idx + 6'd1;
            end
        end else begin
            out_valid <= 1'b0;
        end
    end
endmodule
