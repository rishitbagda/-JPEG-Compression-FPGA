`timescale 1ns/1ps

// End-to-end check of dct_quant_top: wiring + stream-order Q alignment.
// The raw DCT stream is tapped from the DUT (the DCT itself is verified by
// tb_dct_2d_full), then every quantized output is checked against the model
// using an independently built Q table and the stream-order mapping.
module tb_dct_quant;

    localparam integer QUALITY  = 50;     // must match quant_rom.sv
    localparam integer N_BLOCKS = 300;

    logic clk = 0, rst_n = 0, in_valid = 0;
    logic [7:0] pixel_in = 0;
    logic out_valid;
    logic signed [11:0] q_out;
    always #5 clk = ~clk;

    dct_quant_top dut (.clk(clk), .rst_n(rst_n), .in_valid(in_valid),
                       .pixel_in(pixel_in), .out_valid(out_valid), .q_out(q_out));

    // raw DCT stream (tap)
    wire               raw_valid = dut.dct_valid;
    wire signed [13:0] raw_coeff = dut.dct_coeff;

    localparam logic [511:0] LUMA_PACK = {
        8'd16, 8'd11, 8'd10, 8'd16, 8'd24, 8'd40, 8'd51, 8'd61,
        8'd12, 8'd12, 8'd14, 8'd19, 8'd26, 8'd58, 8'd60, 8'd55,
        8'd14, 8'd13, 8'd16, 8'd24, 8'd40, 8'd57, 8'd69, 8'd56,
        8'd14, 8'd17, 8'd22, 8'd29, 8'd51, 8'd87, 8'd80, 8'd62,
        8'd18, 8'd22, 8'd37, 8'd56, 8'd68, 8'd109, 8'd103, 8'd77,
        8'd24, 8'd35, 8'd55, 8'd64, 8'd81, 8'd104, 8'd113, 8'd92,
        8'd49, 8'd64, 8'd78, 8'd87, 8'd103, 8'd121, 8'd120, 8'd101,
        8'd72, 8'd92, 8'd95, 8'd98, 8'd112, 8'd100, 8'd103, 8'd99
    };
    integer lum [0:63];
    integer qs  [0:63];     // Q in stream order
    integer order [0:7];

    reg [31:0] rng = 32'hDEADBEEF;
    function automatic integer rnd(input integer lo, input integer hi);
        reg [31:0] x; integer n, m;
        begin
            x = rng; x = x ^ (x << 13); x = x ^ (x >> 17); x = x ^ (x << 5); rng = x;
            n = hi - lo + 1; m = x % n; rnd = lo + m;
        end
    endfunction

    function automatic integer model_q(input integer x, input integer i);
        integer a, m, r, v;
        begin
            r = (2*65536 + qs[i]) / (2*qs[i]);
            a = (x < 0) ? -x : x;
            m = (a * r + 32768) >> 16;
            v = (x < 0) ? -m : m;
            if (v > 2047) v = 2047;
            if (v < -2048) v = -2048;
            model_q = v;
        end
    endfunction

    integer raw_fifo [0:N_BLOCKS*64+255];
    integer n_raw = 0, n_q = 0, errs = 0, printed = 0;

    always @(posedge clk) if (rst_n) begin
        if (raw_valid) begin raw_fifo[n_raw] = raw_coeff; n_raw = n_raw + 1; end
        if (out_valid) begin
            if (n_q >= n_raw) begin
                errs = errs + 1;
            end else if (q_out != model_q(raw_fifo[n_q], n_q % 64)) begin
                errs = errs + 1;
                if (printed < 15) begin
                    $display("MISMATCH out#%0d idx=%0d raw=%0d actual=%0d expected=%0d",
                             n_q, n_q % 64, raw_fifo[n_q], q_out,
                             model_q(raw_fifo[n_q], n_q % 64));
                    printed = printed + 1;
                end
            end
            n_q = n_q + 1;
        end
    end

    integer b, r, c, g, k, scale, base, gx, gy;
    initial begin
        for (g = 0; g < 64; g = g + 1) lum[g] = LUMA_PACK[(63-g)*8 +: 8];
        scale = (QUALITY < 50) ? 5000 / QUALITY : 200 - 2*QUALITY;
        order[0]=0; order[1]=2; order[2]=4; order[3]=6;
        order[4]=1; order[5]=3; order[6]=5; order[7]=7;
        for (g = 0; g < 8; g = g + 1)
            for (k = 0; k < 8; k = k + 1) begin
                // Q[v][u], u = order[g] (horizontal), v = order[k] (vertical)
                qs[g*8+k] = (lum[order[k]*8 + order[g]] * scale + 50) / 100;
                if (qs[g*8+k] < 1) qs[g*8+k] = 1;
                if (qs[g*8+k] > 255) qs[g*8+k] = 255;
            end

        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1;

        for (b = 0; b < N_BLOCKS; b = b + 1) begin
            base = rnd(20, 235); gx = rnd(-12, 12); gy = rnd(-12, 12);
            for (r = 0; r < 8; r = r + 1)
                for (c = 0; c < 8; c = c + 1) begin
                    @(negedge clk);
                    in_valid = 1;
                    case (b % 3)
                        0: pixel_in = rnd(0, 255);
                        1: pixel_in = (base + gx*c + gy*r + rnd(-6, 6) < 0) ? 0 :
                                      (base + gx*c + gy*r + rnd(-6, 6) > 255) ? 255 :
                                      base + gx*c + gy*r + rnd(-6, 6);
                        default: pixel_in = ((r + c) % 2) ? 255 : 0;
                    endcase
                end
        end
        @(negedge clk); in_valid = 0;
        repeat (400) @(negedge clk);

        $display("\n================================");
        $display("DCT + QUANTIZER INTEGRATION");
        $display("raw coefficients = %0d, quantized outputs = %0d (expected %0d)",
                 n_raw, n_q, N_BLOCKS*64);
        $display("mismatches       = %0d", errs);
        if (errs == 0 && n_q == N_BLOCKS*64) $display("ALL TESTS PASSED");
        else                                 $display("REGRESSION FAILED");
        $display("================================");
        $finish;
    end
endmodule
