`timescale 1ns/1ps

// Run-length encoding of one zigzag-ordered quantized 8x8 coefficient stream.
// One input coefficient per in_valid cycle, 64 per block.
// Emits at most one token per input cycle:
//   DC token : is_dc=1, size=SSSS(diff), amp=encoded diff   (diff vs previous block DC)
//   AC token : is_dc=0, run=RRRR, size=SSSS, amp=encoded coefficient
//   ZRL token: is_dc=0, run=15, size=0 (emitted eagerly on every 16th zero)
//   EOB token: is_dc=0, run=0,  size=0 (trailing zeros at end of block)
// out_last marks the final token of each block.
//
// Magnitudes are clamped to the JPEG baseline range (AC <= 1023, DC diff
// <= 2047). For 8-bit input with the standard quality-50 tables this never
// triggers (|AC| <= 204, |DC diff| <= 128); it only keeps a pathological
// stream legal.
module rle_encode (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic signed [11:0] in_coeff,
    output logic               out_valid,
    output logic               out_last,
    output logic               out_is_dc,
    output logic [3:0]         out_run,
    output logic [3:0]         out_size,
    output logic [10:0]        out_amp
);
    logic [5:0]         idx;      // coefficient position in block, 0..63
    logic [3:0]         run;      // pending zero run
    logic signed [11:0] prev_dc;

    // size category: number of significant bits of mag (mag <= 2047 -> 0..11)
    function automatic logic [3:0] size_of(input logic [10:0] mag);
        logic [3:0] s;
        begin
            s = 4'd0;
            for (int b = 0; b < 11; b++)
                if (mag >= (11'd1 << b)) s = b[3:0] + 4'd1;
            return s;
        end
    endfunction

    // ---- DC path (combinational) ----
    logic signed [12:0] dc_diff_raw;
    logic signed [11:0] dc_v;
    logic [10:0]        dc_mag;
    logic [3:0]         dc_size;
    logic [10:0]        dc_amp;
    always_comb begin
        dc_diff_raw = $signed({in_coeff[11], in_coeff}) - $signed({prev_dc[11], prev_dc});
        // clamp to +/-2047 (baseline DC size category max 11)
        if (dc_diff_raw > 13'sd2047)       dc_v = 12'sd2047;
        else if (dc_diff_raw < -13'sd2047) dc_v = -12'sd2047;
        else                               dc_v = dc_diff_raw[11:0];
        dc_mag  = (dc_v < 0) ? 11'(-dc_v) : 11'(dc_v);
        dc_size = size_of(dc_mag);
        dc_amp  = (dc_v >= 0) ? dc_mag : ((11'd1 << dc_size) - 11'd1) - dc_mag;
    end

    // ---- AC path (combinational) ----
    logic [11:0] ac_mag_full;
    logic [10:0] ac_mag;
    logic [3:0]  ac_size;
    logic [10:0] ac_amp;
    always_comb begin
        ac_mag_full = (in_coeff < 0) ? 12'(-in_coeff) : 12'(in_coeff);
        // clamp to 1023 (baseline AC size category max is 10)
        ac_mag  = (ac_mag_full > 12'd1023) ? 11'd1023 : ac_mag_full[10:0];
        ac_size = size_of(ac_mag);
        ac_amp  = (in_coeff >= 0) ? ac_mag : ((11'd1 << ac_size) - 11'd1) - ac_mag;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx       <= 6'd0;
            run       <= 4'd0;
            prev_dc   <= 12'sd0;
            out_valid <= 1'b0;
            out_last  <= 1'b0;
            out_is_dc <= 1'b0;
            out_run   <= 4'd0;
            out_size  <= 4'd0;
            out_amp   <= 11'd0;
        end else begin
            out_valid <= 1'b0;
            out_last  <= 1'b0;
            if (in_valid) begin
                if (idx == 6'd0) begin
                    // ---- DC coefficient ----
                    out_valid <= 1'b1;
                    out_is_dc <= 1'b1;
                    out_run   <= 4'd0;
                    out_size  <= dc_size;
                    out_amp   <= dc_amp;
                    prev_dc   <= in_coeff;
                    run       <= 4'd0;   // new block always starts with run = 0
                    idx       <= 6'd1;
                end else if (in_coeff == 12'sd0) begin
                    // ---- zero run ----
                    if (run == 4'd15) begin
                        // 16th zero: emit ZRL eagerly
                        out_valid <= 1'b1;
                        out_is_dc <= 1'b0;
                        out_run   <= 4'd15;
                        out_size  <= 4'd0;
                        out_amp   <= 11'd0;
                        run       <= 4'd0;
                        if (idx == 6'd63) out_last <= 1'b1; // all 63 ACs encoded
                    end else begin
                        run <= run + 4'd1;
                        if (idx == 6'd63) begin
                            // trailing zeros: emit EOB
                            out_valid <= 1'b1;
                            out_is_dc <= 1'b0;
                            out_run   <= 4'd0;
                            out_size  <= 4'd0;
                            out_amp   <= 11'd0;
                            out_last  <= 1'b1;
                        end
                    end
                    idx <= (idx == 6'd63) ? 6'd0 : idx + 6'd1;
                end else begin
                    // ---- nonzero AC coefficient ----
                    out_valid <= 1'b1;
                    out_is_dc <= 1'b0;
                    out_run   <= run;
                    out_size  <= ac_size;
                    out_amp   <= ac_amp;
                    run       <= 4'd0;
                    if (idx == 6'd63) out_last <= 1'b1;
                    idx <= (idx == 6'd63) ? 6'd0 : idx + 6'd1;
                end
            end
        end
    end
endmodule
