`timescale 1ns/1ps

// ============================================================================
// quantizer : q = round_half_away( coeff / Q[idx] ), one coefficient per clock
//
//   * Input is the DCT stream (F0,F2,F4,F6,F1,F3,F5,F7 in both dimensions).
//     A 6-bit counter that advances on in_valid selects the reciprocal from
//     quant_rom_luma / quant_rom_chroma (chosen by IS_CHROMA), which is already stored in stream order.
//   * Division is replaced by a multiply with R = round(65536/Q):
//         |q| = (|x| * R + 32768) >> 16
//   * Output saturates to 12-bit signed. Real 8-bit JPEG data stays within
//     about +/-1030 so saturation never triggers in normal operation.
//   * Latency: 3 clocks. Throughput: 1 coefficient per clock.
//   * Alignment: idx wraps every 64 valid inputs and clears on reset, so the
//     first valid input after reset must be coefficient 0 of a block.
// ============================================================================
module quantizer #(
    parameter bit IS_CHROMA = 1'b0     // 0: luminance table (Y), 1: chrominance table (Cb/Cr)
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic signed [13:0] in_coeff,

    output logic               out_valid,
    output logic signed [11:0] out_q
);
    // ---------------------------------------------------------------- index
    logic [5:0]  idx;
    logic [16:0] recip;

    generate
        if (IS_CHROMA) begin : g_chroma
            quant_rom_chroma u_rom (.idx(idx), .recip(recip));
        end else begin : g_luma
            quant_rom_luma u_rom (.idx(idx), .recip(recip));
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)        idx <= 6'd0;
        else if (in_valid) idx <= idx + 6'd1;      // wraps at 64
    end

    // ---------------------------------------------------------------- stage 1
    // sign / magnitude split and reciprocal fetch
    wire [13:0] in_u   = in_coeff;
    wire [13:0] in_abs = in_u[13] ? (14'd0 - in_u) : in_u;   // -8192 -> 8192 fits

    logic        s1_valid, s1_neg;
    logic [13:0] s1_abs;
    logic [16:0] s1_recip;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid <= 1'b0;
            s1_neg   <= 1'b0;
            s1_abs   <= 14'd0;
            s1_recip <= 17'd0;
        end else begin
            s1_valid <= in_valid;
            s1_neg   <= in_u[13];
            s1_abs   <= in_abs;
            s1_recip <= recip;
        end
    end

    // ---------------------------------------------------------------- stage 2
    // multiply, add rounding constant, drop 16 fractional bits
    wire [31:0] prod = s1_abs * s1_recip;
    wire [31:0] rnd  = prod + 32'd32768;

    logic        s2_valid, s2_neg;
    logic [13:0] s2_mag;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid <= 1'b0;
            s2_neg   <= 1'b0;
            s2_mag   <= 14'd0;
        end else begin
            s2_valid <= s1_valid;
            s2_neg   <= s1_neg;
            s2_mag   <= rnd[29:16];            // max 8192 -> 14 bits
        end
    end

    // ---------------------------------------------------------------- stage 3
    // re-apply sign, saturate to 12-bit signed
    logic signed [15:0] signed_val;
    always_comb begin
        signed_val = s2_neg ? -$signed({2'b00, s2_mag}) : $signed({2'b00, s2_mag});
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid <= 1'b0;
            out_q     <= 12'sd0;
        end else begin
            out_valid <= s2_valid;
            if (signed_val > 16'sd2047)       out_q <= 12'sd2047;
            else if (signed_val < -16'sd2048) out_q <= -12'sd2048;
            else                              out_q <= signed_val[11:0];
        end
    end
endmodule
