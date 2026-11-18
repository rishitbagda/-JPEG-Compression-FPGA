`timescale 1ns/1ps

// ============================================================================
// tb_dct_2d_full : extended regression for dct_2d_top
//
// Checks performed
//   1. Bit-exact compare against a fixed-point model of dct_1d / transpose.
//   2. Accuracy compare against an ideal floating-point 8x8 DCT-II (JPEG scale).
//   3. Output protocol: no X on out_valid / data, outputs arrive in runs that
//      are a multiple of 64, no extra / missing outputs.
//
// Stimulus phases (all use the same pre-generated block list)
//   P0  single block after reset
//   P1  continuous back-to-back blocks, no reset, no gaps
//   P2  random idle gaps between blocks (garbage driven on pixel_in while idle)
//   P3  random stalls inside a block at positions the design supports
//   P4  reset while blocks are in flight, then recovery run
//   P5  (optional, ENABLE_ARBITRARY_STALLS=1) stalls anywhere, informational
//
// Output order of dct_2d_top (both dimensions): F0,F2,F4,F6,F1,F3,F5,F7
//   out index = group*8 + k, group = horizontal freq slot, k = vertical freq slot
// ============================================================================
module tb_dct_2d_full;

    // ------------------------------------------------------------------ config
    localparam integer N_RANDOM_PER_TYPE      = 300;   // random blocks per random kind
    localparam integer MAX_BLOCKS             = 4096;
    localparam real    FLOAT_TOL              = 16.0;  // max |hw - ideal DCT| allowed
    localparam integer ENABLE_ARBITRARY_STALLS = 0;    // 1 = run informational P5
    localparam integer MAX_PRINT              = 20;    // max mismatch lines per phase

    localparam real PI = 3.14159265358979323846;

    // block kinds
    localparam integer K_CONST       = 0;
    localparam integer K_IMPULSE     = 1;
    localparam integer K_BASIS       = 2;
    localparam integer K_HRAMP       = 3;
    localparam integer K_VRAMP       = 4;
    localparam integer K_DIAG        = 5;
    localparam integer K_CHECK       = 6;
    localparam integer K_HSTRIPE     = 7;
    localparam integer K_VSTRIPE     = 8;
    localparam integer K_RAND_UNI    = 9;
    localparam integer K_RAND_EXT    = 10;
    localparam integer K_RAND_SMALL  = 11;
    localparam integer K_RAND_SPARSE = 12;
    localparam integer K_RAND_GRAD   = 13;
    localparam integer N_KINDS       = 14;

    // ------------------------------------------------------------------ DUT
    logic               clk = 0;
    logic               rst_n = 0;
    logic               in_valid = 0;
    logic [7:0]         pixel_in = 0;
    logic               out_valid;
    logic signed [13:0] dct_coeff_out;

    dct_2d_top dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .pixel_in(pixel_in),
        .out_valid(out_valid), .dct_coeff_out(dct_coeff_out)
    );

    always #5 clk = ~clk;

    // ------------------------------------------------------------------ storage
    integer blk_pix  [0:MAX_BLOCKS*64-1];   // pixel values 0..255
    integer exp_mem  [0:MAX_BLOCKS*64-1];   // bit-exact expected output stream
    real    exp_f    [0:MAX_BLOCKS*64-1];   // ideal floating-point expected stream
    integer blk_kind [0:MAX_BLOCKS-1];
    integer blk_err  [0:MAX_BLOCKS-1];      // mismatches seen per block (current phase)
    integer kind_err [0:N_KINDS-1];
    integer kind_cnt [0:N_KINDS-1];
    integer nblocks = 0;

    integer coeff_index [0:7];

    // ------------------------------------------------------------------ RNG
    reg [31:0] rng = 32'h1BADB002;

    function automatic integer rnd(input integer lo, input integer hi);
        reg [31:0] x;
        integer    n, m;
        begin
            x   = rng;
            x   = x ^ (x << 13);
            x   = x ^ (x >> 17);
            x   = x ^ (x << 5);
            rng = x;
            n   = hi - lo + 1;
            m   = x % n;
            rnd = lo + m;
        end
    endfunction

    function automatic integer clamp255(input integer v);
        begin
            if (v < 0)        clamp255 = 0;
            else if (v > 255) clamp255 = 255;
            else              clamp255 = v;
        end
    endfunction

    function automatic integer wrap12(input integer v);
        reg signed [11:0] t;
        begin t = v; wrap12 = t; end
    endfunction

    function automatic integer wrap14(input integer v);
        reg signed [13:0] t;
        begin t = v; wrap14 = t; end
    endfunction

    // ------------------------------------------------------------------ 1-D model
    // Same equations / constants / +128 rounding as dct_1d.sv.
    // Input m_x[], output m_y[] in streaming order F0,F2,F4,F6,F1,F3,F5,F7.
    integer m_x [0:7];
    integer m_y [0:7];
    integer m_row;

    task automatic model_1d;
        integer p3,p2,p1,p0,d3,d2,d1,d0;
        integer f0,f2,f4,f6,f1,f3,f5,f7;
        integer k;
        integer s [0:7];
        begin
            p3 = m_x[3]+m_x[4]; p2 = m_x[2]+m_x[5];
            p1 = m_x[1]+m_x[6]; p0 = m_x[0]+m_x[7];
            d3 = m_x[3]-m_x[4]; d2 = m_x[2]-m_x[5];
            d1 = m_x[1]-m_x[6]; d0 = m_x[0]-m_x[7];

            f0 = (90*(p3+p2+p1+p0) + 128) >>> 8;
            f2 = ((-118*p3 - 49*p2 + 49*p1 + 118*p0) + 128) >>> 8;
            f4 = (90*(p3-p2-p1+p0) + 128) >>> 8;
            f6 = ((-49*p3 + 118*p2 - 118*p1 + 49*p0) + 128) >>> 8;

            f1 = ((25*d3 + 71*d2 + 106*d1 + 125*d0) + 128) >>> 8;
            f3 = ((-71*d3 - 125*d2 - 25*d1 + 106*d0) + 128) >>> 8;
            f5 = ((106*d3 + 25*d2 - 125*d1 + 71*d0) + 128) >>> 8;
            f7 = ((-125*d3 + 106*d2 - 71*d1 + 25*d0) + 128) >>> 8;

            s[0]=f0; s[1]=f2; s[2]=f4; s[3]=f6;
            s[4]=f1; s[5]=f3; s[6]=f5; s[7]=f7;

            for (k = 0; k < 8; k = k + 1)
                m_y[k] = (m_row != 0) ? wrap12(s[k]) : wrap14(s[k]);
        end
    endtask

    // ------------------------------------------------------------------ expected
    integer inter [0:7][0:7];   // row-pass results, streaming order

    task automatic build_expected(input integer b);
        integer r, c, g, k, u, v, px;
        real    acc, cu, cv;
        begin
            // fixed-point model: row pass, transpose, column pass
            for (r = 0; r < 8; r = r + 1) begin
                for (c = 0; c < 8; c = c + 1)
                    m_x[c] = blk_pix[b*64 + r*8 + c] - 128;
                m_row = 1;
                model_1d;
                for (g = 0; g < 8; g = g + 1)
                    inter[r][g] = m_y[g];
            end
            for (g = 0; g < 8; g = g + 1) begin
                for (r = 0; r < 8; r = r + 1)
                    m_x[r] = inter[r][g];
                m_row = 0;
                model_1d;
                for (k = 0; k < 8; k = k + 1)
                    exp_mem[b*64 + g*8 + k] = m_y[k];
            end

            // ideal floating-point 2-D DCT-II, JPEG normalisation
            for (g = 0; g < 8; g = g + 1) begin
                for (k = 0; k < 8; k = k + 1) begin
                    u = coeff_index[g];   // horizontal frequency
                    v = coeff_index[k];   // vertical frequency
                    acc = 0.0;
                    for (r = 0; r < 8; r = r + 1)
                        for (c = 0; c < 8; c = c + 1) begin
                            px  = blk_pix[b*64 + r*8 + c] - 128;
                            acc = acc + px * $cos((2*c+1)*u*PI/16.0)
                                           * $cos((2*r+1)*v*PI/16.0);
                        end
                    cu = (u == 0) ? 0.70710678118654752 : 1.0;
                    cv = (v == 0) ? 0.70710678118654752 : 1.0;
                    exp_f[b*64 + g*8 + k] = 0.25 * cu * cv * acc;
                end
            end
        end
    endtask

    // ------------------------------------------------------------------ block generation
    function automatic string kind_name(input integer k);
        begin
            case (k)
                K_CONST:       kind_name = "const";
                K_IMPULSE:     kind_name = "impulse";
                K_BASIS:       kind_name = "dct-basis";
                K_HRAMP:       kind_name = "h-ramp";
                K_VRAMP:       kind_name = "v-ramp";
                K_DIAG:        kind_name = "diagonal";
                K_CHECK:       kind_name = "checker";
                K_HSTRIPE:     kind_name = "row-stripes";
                K_VSTRIPE:     kind_name = "col-stripes";
                K_RAND_UNI:    kind_name = "rand-uniform";
                K_RAND_EXT:    kind_name = "rand-0/255";
                K_RAND_SMALL:  kind_name = "rand-small";
                K_RAND_SPARSE: kind_name = "rand-sparse";
                K_RAND_GRAD:   kind_name = "rand-gradient";
                default:       kind_name = "?";
            endcase
        end
    endfunction

    task automatic add_block(input integer kind, input integer a,
                             input integer b, input integer c);
        integer r, col, i, n, base, gx, gy, v, base_i;
        real    t;
        begin
            if (nblocks >= MAX_BLOCKS) begin
                $display("FATAL: MAX_BLOCKS too small");
                $finish;
            end
            base_i = nblocks * 64;
            for (r = 0; r < 8; r = r + 1) begin
                for (col = 0; col < 8; col = col + 1) begin
                    i = r*8 + col;
                    case (kind)
                        K_CONST:   v = a;
                        K_IMPULSE: v = (i == a) ? b : c;
                        K_BASIS: begin
                            t = 127.0 * $cos((2*col+1)*a*PI/16.0)
                                      * $cos((2*r+1)*b*PI/16.0);
                            v = 128 + c * ((t >= 0.0) ? $rtoi(t + 0.5) : -$rtoi(-t + 0.5));
                        end
                        K_HRAMP:   v = b + a*col;
                        K_VRAMP:   v = b + a*r;
                        K_DIAG:    v = b + a*(r + col);
                        K_CHECK:   v = (((r + col + c) % 2) == 0) ? a : b;
                        K_HSTRIPE: v = ((r % 2) == 0) ? a : b;
                        K_VSTRIPE: v = ((col % 2) == 0) ? a : b;
                        K_RAND_UNI:   v = rnd(0, 255);
                        K_RAND_EXT:   v = (rnd(0, 1) == 1) ? 255 : 0;
                        K_RAND_SMALL: v = 128 + rnd(-a, a);
                        default:      v = 128;   // sparse / gradient filled below
                    endcase
                    blk_pix[base_i + i] = clamp255(v);
                end
            end

            if (kind == K_RAND_SPARSE) begin
                n = a;
                for (i = 0; i < n; i = i + 1)
                    blk_pix[base_i + rnd(0, 63)] = rnd(0, 255);
            end

            if (kind == K_RAND_GRAD) begin
                base = rnd(40, 215);
                gx   = rnd(-12, 12);
                gy   = rnd(-12, 12);
                for (r = 0; r < 8; r = r + 1)
                    for (col = 0; col < 8; col = col + 1)
                        blk_pix[base_i + r*8 + col] =
                            clamp255(base + gx*col + gy*r + rnd(-a, a));
            end

            blk_kind[nblocks] = kind;
            kind_cnt[kind]    = kind_cnt[kind] + 1;
            build_expected(nblocks);
            nblocks = nblocks + 1;
        end
    endtask

    task automatic build_block_list;
        integer i, u, v, n;
        begin
            // constants
            add_block(K_CONST, 0,   0, 0);
            add_block(K_CONST, 1,   0, 0);
            add_block(K_CONST, 127, 0, 0);
            add_block(K_CONST, 128, 0, 0);
            add_block(K_CONST, 129, 0, 0);
            add_block(K_CONST, 254, 0, 0);
            add_block(K_CONST, 255, 0, 0);

            // impulses at every position, four polarity / background combos
            for (i = 0; i < 64; i = i + 1) begin
                add_block(K_IMPULSE, i, 255, 128);
                add_block(K_IMPULSE, i, 0,   128);
                add_block(K_IMPULSE, i, 255, 0);
                add_block(K_IMPULSE, i, 0,   255);
            end

            // every 2-D DCT basis pattern, both polarities
            for (u = 0; u < 8; u = u + 1)
                for (v = 0; v < 8; v = v + 1) begin
                    add_block(K_BASIS, u, v,  1);
                    add_block(K_BASIS, u, v, -1);
                end

            // ramps / gradients
            add_block(K_HRAMP,  32, 0,   0);
            add_block(K_HRAMP,  36, 0,   0);
            add_block(K_HRAMP, -32, 224, 0);
            add_block(K_HRAMP,  16, 64,  0);
            add_block(K_VRAMP,  32, 0,   0);
            add_block(K_VRAMP,  36, 0,   0);
            add_block(K_VRAMP, -32, 224, 0);
            add_block(K_VRAMP,  16, 64,  0);
            add_block(K_DIAG,   16, 0,   0);
            add_block(K_DIAG,  -16, 224, 0);
            add_block(K_DIAG,    8, 100,  0);

            // checkerboards / stripes (extreme and moderate swings)
            add_block(K_CHECK, 255, 0,   0);
            add_block(K_CHECK, 255, 0,   1);
            add_block(K_CHECK, 200, 50,  0);
            add_block(K_CHECK, 129, 128, 0);
            add_block(K_HSTRIPE, 255, 0,   0);
            add_block(K_HSTRIPE, 255, 128, 0);
            add_block(K_HSTRIPE, 0,   255, 0);
            add_block(K_VSTRIPE, 255, 0,   0);
            add_block(K_VSTRIPE, 255, 128, 0);
            add_block(K_VSTRIPE, 0,   255, 0);

            // random families
            for (n = 0; n < N_RANDOM_PER_TYPE; n = n + 1) begin
                add_block(K_RAND_UNI,    0, 0, 0);
                add_block(K_RAND_EXT,    0, 0, 0);
                add_block(K_RAND_SMALL,  1 + (n % 6), 0, 0);   // +/-1 .. +/-6
                add_block(K_RAND_SPARSE, 1 + (n % 8), 0, 0);   // 1..8 outliers
                add_block(K_RAND_GRAD,   (n % 3) * 4, 0, 0);   // noise 0,4,8
            end
        end
    endtask

    // ------------------------------------------------------------------ monitor
    integer out_count   = 0;
    integer exp_total   = 0;     // outputs expected in the current phase
    integer error_count = 0;     // all failures, all phases
    integer phase_err   = 0;     // mismatches in the current phase
    integer proto_err   = 0;
    integer float_viol  = 0;
    integer run_len     = 0;
    bit     check_en    = 0;
    integer printed     = 0;

    real    f_max       = 0.0;
    real    f_sum       = 0.0;
    integer f_n         = 0;
    real    f_pos_max [0:63];

    task automatic clear_phase_stats;
        integer i;
        begin
            out_count = 0;
            run_len   = 0;
            phase_err = 0;
            printed   = 0;
            f_max     = 0.0;
            f_sum     = 0.0;
            f_n       = 0;
            for (i = 0; i < MAX_BLOCKS; i = i + 1) blk_err[i] = 0;
            for (i = 0; i < 64; i = i + 1) f_pos_max[i] = 0.0;
        end
    endtask

    integer act, blk_i, pos_i;
    real    ferr;

    always @(posedge clk) begin
        if (rst_n && check_en) begin
            if ($isunknown(out_valid)) begin
                $display("[%0t] ERROR: out_valid is X/Z", $time);
                proto_err = proto_err + 1; error_count = error_count + 1;
            end else if (out_valid) begin
                if ($isunknown(dct_coeff_out)) begin
                    $display("[%0t] ERROR: dct_coeff_out is X/Z while out_valid", $time);
                    proto_err = proto_err + 1; error_count = error_count + 1;
                end else if (out_count >= exp_total) begin
                    if (printed < MAX_PRINT)
                        $display("[%0t] ERROR: extra output #%0d (expected only %0d)",
                                 $time, out_count, exp_total);
                    printed = printed + 1;
                    proto_err = proto_err + 1; error_count = error_count + 1;
                end else begin
                    act   = dct_coeff_out;
                    blk_i = out_count / 64;
                    pos_i = out_count % 64;

                    if (act != exp_mem[out_count]) begin
                        blk_err[blk_i]          = blk_err[blk_i] + 1;
                        kind_err[blk_kind[blk_i]] = kind_err[blk_kind[blk_i]] + 1;
                        phase_err   = phase_err + 1;
                        error_count = error_count + 1;
                        if (printed < MAX_PRINT) begin
                            $display("MISMATCH blk=%0d (%s) idx=%0d actual=%0d expected=%0d",
                                     blk_i, kind_name(blk_kind[blk_i]), pos_i,
                                     act, exp_mem[out_count]);
                            printed = printed + 1;
                        end
                    end

                    ferr = act - exp_f[out_count];
                    if (ferr < 0.0) ferr = -ferr;
                    f_sum = f_sum + ferr;
                    f_n   = f_n + 1;
                    if (ferr > f_max) f_max = ferr;
                    if (ferr > f_pos_max[pos_i]) f_pos_max[pos_i] = ferr;
                    if (ferr > FLOAT_TOL) begin
                        float_viol  = float_viol + 1;
                        error_count = error_count + 1;
                        if (printed < MAX_PRINT) begin
                            $display("ACCURACY blk=%0d (%s) idx=%0d hw=%0d ideal=%f err=%f",
                                     blk_i, kind_name(blk_kind[blk_i]), pos_i,
                                     act, exp_f[out_count], ferr);
                            printed = printed + 1;
                        end
                    end
                end
                out_count = out_count + 1;
                run_len   = run_len + 1;
            end else begin
                if (run_len != 0 && (run_len % 64) != 0) begin
                    $display("[%0t] ERROR: out_valid run of %0d cycles (not a multiple of 64)",
                             $time, run_len);
                    proto_err = proto_err + 1; error_count = error_count + 1;
                end
                run_len = 0;
            end
        end
    end

    // ------------------------------------------------------------------ driver
    bit garbage_en = 1;

    task automatic send_pixel(input integer val);
        begin
            @(negedge clk);
            in_valid = 1;
            pixel_in = val[7:0];
        end
    endtask

    task automatic idle_cycles(input integer n);
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) begin
                @(negedge clk);
                in_valid = 0;
                pixel_in = garbage_en ? rnd(0, 255) : 8'd0;
            end
        end
    endtask

    task automatic apply_reset(input integer cycles);
        begin
            @(negedge clk);
            rst_n = 0; in_valid = 0; pixel_in = 0;
            repeat (cycles) @(negedge clk);
            rst_n = 1;
        end
    endtask

    // gap_mode: 0 none, 1 random gaps between blocks
    // stall_mode: 0 none, 1 stalls only where supported, 2 stalls anywhere
    task automatic run_stream(input integer first, input integer count,
                              input integer gap_mode, input integer stall_mode);
        integer b, r, c, gap, q;
        begin
            for (b = first; b < first + count; b = b + 1) begin
                if (gap_mode == 1) begin
                    q = rnd(0, 9);
                    if (q < 4)      gap = 0;
                    else if (q < 8) gap = rnd(1, 16);
                    else            gap = rnd(17, 150);
                    if (gap > 0) idle_cycles(gap);
                end
                for (r = 0; r < 8; r = r + 1) begin
                    for (c = 0; c < 8; c = c + 1) begin
                        // stalls before sample c of the row. Samples 4..7 of a row
                        // must stay contiguous in dct_1d, so mode 1 only stalls
                        // before c = 0..4.
                        if (stall_mode == 1 && c <= 4 && rnd(0, 7) == 0)
                            idle_cycles(rnd(1, 5));
                        if (stall_mode == 2 && rnd(0, 15) == 0)
                            idle_cycles(rnd(1, 5));
                        send_pixel(blk_pix[b*64 + r*8 + c]);
                    end
                end
            end
            idle_cycles(1);
        end
    endtask

    // wait for exp_total outputs (with timeout) and a margin to catch extras
    task automatic drain;
        integer t;
        begin
            t = 0;
            while (out_count < exp_total && t < 3000) begin
                @(negedge clk);
                t = t + 1;
            end
            repeat (200) @(negedge clk);
        end
    endtask

    // ------------------------------------------------------------------ reporting
    time    t_first_in;
    time    t_last_out;

    task automatic report_phase(input string name, input integer nb);
        integer i, shown;
        real    mean;
        begin
            mean = (f_n > 0) ? f_sum / f_n : 0.0;
            if (out_count != exp_total) begin
                $display("ERROR: %s expected %0d outputs, received %0d",
                         name, exp_total, out_count);
                proto_err   = proto_err + 1;
                error_count = error_count + 1;
            end
            shown = 0;
            for (i = 0; i < nb && shown < 10; i = i + 1)
                if (blk_err[i] != 0) begin
                    $display("  bad block %0d (%s): %0d mismatches",
                             i, kind_name(blk_kind[i]), blk_err[i]);
                    shown = shown + 1;
                end
            $display("%s: blocks=%0d outputs=%0d mismatches=%0d | ideal-DCT err max=%f mean=%f",
                     name, nb, out_count, phase_err, f_max, mean);
            if (phase_err == 0 && out_count == exp_total)
                $display("PASS: %s", name);
            else
                $display("FAIL: %s", name);
        end
    endtask

    // ------------------------------------------------------------------ main
    integer i_main;

    initial begin
        #500_000_000;
        $display("TIMEOUT: simulation exceeded limit");
        $finish;
    end

    initial begin
        coeff_index[0]=0; coeff_index[1]=2; coeff_index[2]=4; coeff_index[3]=6;
        coeff_index[4]=1; coeff_index[5]=3; coeff_index[6]=5; coeff_index[7]=7;
        for (i_main = 0; i_main < N_KINDS; i_main = i_main + 1) begin
            kind_err[i_main] = 0;
            kind_cnt[i_main] = 0;
        end

        $display("Building stimulus and reference ...");
        build_block_list;
        $display("Built %0d blocks (%0d outputs)", nblocks, nblocks*64);
        for (i_main = 0; i_main < N_KINDS; i_main = i_main + 1)
            $display("  kind %-14s : %0d blocks", kind_name(i_main), kind_cnt[i_main]);

        rst_n = 0; in_valid = 0; pixel_in = 0;
        repeat (4) @(negedge clk);
        rst_n = 1;

        // ---- P0: single block
        $display("\n=== P0: single block after reset ===");
        clear_phase_stats; exp_total = 64; check_en = 1;
        run_stream(0, 1, 0, 0);
        drain;
        report_phase("P0 single block", 1);

        // ---- P1: continuous back-to-back, no reset
        $display("\n=== P1: continuous back-to-back, no gaps ===");
        apply_reset(4);
        clear_phase_stats; exp_total = nblocks*64; check_en = 1;
        t_first_in = $time;
        run_stream(0, nblocks, 0, 0);
        drain;
        t_last_out = $time;
        report_phase("P1 back-to-back", nblocks);
        $display("  total P1 time: %0d cycles for %0d blocks (incl. 200-cycle drain margin; ideal ~64/block)",
                 (t_last_out - t_first_in)/10, nblocks);

        // ---- P2: random gaps between blocks, no reset since P1
        $display("\n=== P2: random idle gaps between blocks ===");
        clear_phase_stats; exp_total = nblocks*64;
        run_stream(0, nblocks, 1, 0);
        drain;
        report_phase("P2 random gaps", nblocks);

        // ---- P3: stalls inside blocks (supported positions)
        $display("\n=== P3: random stalls inside blocks (supported positions) ===");
        clear_phase_stats; exp_total = nblocks*64;
        run_stream(0, nblocks, 1, 1);
        drain;
        report_phase("P3 in-block stalls", nblocks);

        // ---- P4: reset while data is in flight, then recover
        $display("\n=== P4: reset with blocks in flight, then recovery ===");
        check_en = 0;
        run_stream(0, 3, 0, 0);
        idle_cycles(100);
        apply_reset(3);
        clear_phase_stats; exp_total = 40*64; check_en = 1;
        run_stream(0, 40, 0, 0);
        drain;
        report_phase("P4 reset recovery", 40);

        // ---- P5: informational, arbitrary stalls
        if (ENABLE_ARBITRARY_STALLS) begin
            $display("\n=== P5: arbitrary stalls anywhere (informational) ===");
            apply_reset(3);
            clear_phase_stats; exp_total = 200*64; check_en = 1;
            begin : p5
                integer saved;
                saved = error_count;
                run_stream(0, 200, 0, 2);
                drain;
                report_phase("P5 arbitrary stalls (informational)", 200);
                error_count = saved;   // do not count against the regression
            end
        end

        // ---- summary
        $display("\n================================================");
        $display("2D DCT EXTENDED REGRESSION");
        $display("Blocks in list        = %0d", nblocks);
        $display("Total errors          = %0d", error_count);
        $display("  protocol errors     = %0d", proto_err);
        $display("  accuracy violations = %0d (tol %f)", float_viol, FLOAT_TOL);
        for (i_main = 0; i_main < N_KINDS; i_main = i_main + 1)
            if (kind_err[i_main] != 0)
                $display("  mismatches in kind %-14s = %0d", kind_name(i_main), kind_err[i_main]);
        if (error_count == 0) $display("ALL TESTS PASSED");
        else                  $display("REGRESSION FAILED");
        $display("================================================");
        $finish;
    end

endmodule
