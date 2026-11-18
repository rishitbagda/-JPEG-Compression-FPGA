`timescale 1ns/1ps

// Standalone quantizer regression.
//   * bit-exact vs reciprocal model (|x|*R + 32768) >> 16, saturated to 12 bits
//   * within +/-1 of true round-half-away division
//   * output valid is the input valid delayed by exactly 3 clocks
// QUALITY / CHROMA must match what gen_quant_rom.py used for quant_rom.sv.
// The Q table is rebuilt here independently of the Python script.
module tb_quantizer;

    localparam integer QUALITY  = 50;
    localparam integer CHROMA   = 0;
    localparam integer N_BLOCKS = 2000;
    localparam integer LATENCY  = 3;

    logic               clk = 0, rst_n = 0, in_valid = 0;
    logic signed [13:0] in_coeff = 0;
    logic               out_valid;
    logic signed [11:0] out_q;

    quantizer #(.IS_CHROMA(CHROMA)) dut (.clk(clk), .rst_n(rst_n), .in_valid(in_valid), .in_coeff(in_coeff),
                   .out_valid(out_valid), .out_q(out_q));
    always #5 clk = ~clk;

    // ------------------------------------------------------------ Q table
    // standard JPEG luminance table, element 0 in the top byte
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
    integer base_luma   [0:63];
    integer base_chroma [0:63];
    integer qnat   [0:7][0:7];   // [v][u]
    integer qstream [0:63];
    integer rstream [0:63];
    integer order [0:7];

    task automatic build_tables;
        integer r, c, scale, q, g, k;
        begin
            for (r = 0; r < 64; r = r + 1) begin
                base_luma[r] = LUMA_PACK[(63-r)*8 +: 8];
                base_chroma[r] = 99;
            end
            base_chroma[0]=17; base_chroma[1]=18; base_chroma[2]=24; base_chroma[3]=47;
            base_chroma[8]=18; base_chroma[9]=21; base_chroma[10]=26; base_chroma[11]=66;
            base_chroma[16]=24; base_chroma[17]=26; base_chroma[18]=56;
            base_chroma[24]=47; base_chroma[25]=66;

            scale = (QUALITY < 50) ? 5000 / QUALITY : 200 - 2*QUALITY;
            for (r = 0; r < 8; r = r + 1)
                for (c = 0; c < 8; c = c + 1) begin
                    q = ((CHROMA ? base_chroma[r*8+c] : base_luma[r*8+c]) * scale + 50) / 100;
                    if (q < 1) q = 1;
                    if (q > 255) q = 255;
                    qnat[r][c] = q;
                end
            order[0]=0; order[1]=2; order[2]=4; order[3]=6;
            order[4]=1; order[5]=3; order[6]=5; order[7]=7;
            for (g = 0; g < 8; g = g + 1)
                for (k = 0; k < 8; k = k + 1) begin
                    q = qnat[order[k]][order[g]];          // [v][u]
                    qstream[g*8+k] = q;
                    rstream[g*8+k] = (2*65536 + q) / (2*q);
                end
        end
    endtask

    // ------------------------------------------------------------ models
    function automatic integer model_recip(input integer x, input integer i);
        integer a, m, v;
        begin
            a = (x < 0) ? -x : x;
            m = (a * rstream[i] + 32768) >> 16;
            v = (x < 0) ? -m : m;
            if (v > 2047)  v = 2047;
            if (v < -2048) v = -2048;
            model_recip = v;
        end
    endfunction

    function automatic integer model_true(input integer x, input integer i);
        integer a, m, v;
        begin
            a = (x < 0) ? -x : x;
            m = (2*a + qstream[i]) / (2*qstream[i]);      // round half away from zero
            v = (x < 0) ? -m : m;
            if (v > 2047)  v = 2047;
            if (v < -2048) v = -2048;
            model_true = v;
        end
    endfunction

    // ------------------------------------------------------------ RNG
    reg [31:0] rng = 32'hC0FFEE11;
    function automatic integer rnd(input integer lo, input integer hi);
        reg [31:0] x; integer n, m;
        begin
            x = rng; x = x ^ (x << 13); x = x ^ (x >> 17); x = x ^ (x << 5); rng = x;
            n = hi - lo + 1; m = x % n; rnd = lo + m;
        end
    endfunction

    // ------------------------------------------------------------ scoreboard
    localparam integer MAXS = N_BLOCKS*64 + 1024;
    integer exp_r [0:MAXS-1];
    integer exp_t [0:MAXS-1];
    integer n_in = 0, n_out = 0, tb_idx = 0;
    integer errs_exact = 0, errs_true = 0, errs_proto = 0, printed = 0;
    integer max_dev = 0;
    bit     check_en = 0;
    logic [LATENCY-1:0] vpipe = 0;
    integer act, dev;

    always @(posedge clk) begin
        if (!rst_n) begin
            vpipe <= 0;
        end else if (check_en) begin
            vpipe <= {vpipe[LATENCY-2:0], in_valid};
            if (in_valid) begin
                exp_r[n_in] = model_recip(in_coeff, tb_idx);
                exp_t[n_in] = model_true(in_coeff, tb_idx);
                n_in   = n_in + 1;
                tb_idx = (tb_idx + 1) % 64;
            end
            // valid must be exactly the 3-cycle-delayed input valid
            if (out_valid !== vpipe[LATENCY-1]) begin
                if (printed < 10)
                    $display("[%0t] ERROR: out_valid=%b, expected %b (latency %0d)",
                             $time, out_valid, vpipe[LATENCY-1], LATENCY);
                printed = printed + 1;
                errs_proto = errs_proto + 1;
            end
            if (out_valid === 1'b1) begin
                act = out_q;
                if (n_out >= n_in) begin
                    errs_proto = errs_proto + 1;
                end else begin
                    if (act != exp_r[n_out]) begin
                        errs_exact = errs_exact + 1;
                        if (printed < 10) begin
                            $display("MISMATCH out#%0d idx=%0d actual=%0d expected=%0d",
                                     n_out, n_out % 64, act, exp_r[n_out]);
                            printed = printed + 1;
                        end
                    end
                    dev = act - exp_t[n_out];
                    if (dev < 0) dev = -dev;
                    if (dev > max_dev) max_dev = dev;
                    if (dev > 1) errs_true = errs_true + 1;
                end
                n_out = n_out + 1;
            end
        end
    end

    // ------------------------------------------------------------ driver
    task automatic send(input integer x);
        begin
            @(negedge clk);
            in_valid = 1; in_coeff = x;
        end
    endtask

    task automatic idle(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk);
                in_valid = 0; in_coeff = rnd(-8192, 8191);   // garbage when invalid
            end
        end
    endtask

    function automatic integer gen_coeff(input integer mode, input integer i);
        integer q, n, s, x;
        begin
            q = qstream[i];
            case (mode)
                0: x = rnd(-8192, 8191);                               // full range
                1: x = rnd(-1024, 1024) >>> rnd(0, 8);                 // realistic, small-heavy
                2: begin                                               // rounding ties +/-1
                    n = rnd(0, 1024 / q);
                    s = rnd(0, 1) ? 1 : -1;
                    x = s * (n*q + q/2 + rnd(-1, 1));
                    if (x > 8191) x = 8191;
                    if (x < -8192) x = -8192;
                end
                default: begin                                         // extremes
                    case (rnd(0, 5))
                        0: x = 8191;  1: x = -8192; 2: x = 0;
                        3: x = 1;     4: x = -1;    default: x = (rnd(0,1) ? q : -q);
                    endcase
                end
            endcase
            gen_coeff = x;
        end
    endfunction

    task automatic run_blocks(input integer nb, input integer gaps);
        integer b, i, mode;
        begin
            for (b = 0; b < nb; b = b + 1) begin
                mode = b % 4;
                for (i = 0; i < 64; i = i + 1) begin
                    if (gaps && rnd(0, 7) == 0) idle(rnd(1, 3));
                    send(gen_coeff(mode, i));
                end
                if (gaps && rnd(0, 3) == 0) idle(rnd(1, 90));
            end
            idle(1);
        end
    endtask

    task automatic drain;
        begin repeat (20) @(negedge clk); end
    endtask

    integer fails;
    initial begin
        #200_000_000 $display("TIMEOUT"); $finish;
    end

    initial begin
        build_tables;
        rst_n = 0; repeat (4) @(negedge clk); rst_n = 1;

        // --- A: continuous
        check_en = 1;
        run_blocks(N_BLOCKS/2, 0);
        drain;
        $display("A continuous : in=%0d out=%0d exact_err=%0d true_err(>1)=%0d max_dev=%0d",
                 n_in, n_out, errs_exact, errs_true, max_dev);

        // --- B: gaps inside and between blocks (counter must advance only on valid)
        run_blocks(N_BLOCKS/2, 1);
        drain;
        $display("B with gaps  : in=%0d out=%0d exact_err=%0d true_err(>1)=%0d max_dev=%0d",
                 n_in, n_out, errs_exact, errs_true, max_dev);

        // --- C: reset in the middle of a block, then re-check alignment
        check_en = 0;
        repeat (37) send(rnd(-1000, 1000));
        @(negedge clk); in_valid = 0; rst_n = 0; repeat (3) @(negedge clk); rst_n = 1;
        n_in = 0; n_out = 0; tb_idx = 0; vpipe = 0; printed = 0;
        check_en = 1;
        run_blocks(40, 0);
        drain;
        $display("C after reset: in=%0d out=%0d exact_err=%0d true_err(>1)=%0d max_dev=%0d",
                 n_in, n_out, errs_exact, errs_true, max_dev);

        if (n_in != n_out) begin
            $display("ERROR: sample count in=%0d out=%0d", n_in, n_out);
            errs_proto = errs_proto + 1;
        end

        fails = errs_exact + errs_true + errs_proto;
        $display("\n================================");
        $display("QUANTIZER REGRESSION");
        $display("bit-exact mismatches   = %0d", errs_exact);
        $display("vs true division (>1)  = %0d (max deviation %0d)", errs_true, max_dev);
        $display("protocol errors        = %0d", errs_proto);
        if (fails == 0) $display("ALL TESTS PASSED");
        else            $display("REGRESSION FAILED");
        $display("================================");
        $finish;
    end
endmodule
