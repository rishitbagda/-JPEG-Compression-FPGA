`timescale 1ns/1ps

// tb_jpeg_encoder_top.sv - end-to-end testbench for the full JPEG encoder.
//
// Drives jpeg_encoder_top with a synthetic test image (W x H, multiples of
// 8), captures the scan byte stream, writes:
//   scan.bin  - raw entropy-coded scan bytes (input to assemble_jpeg.py)
//   input.ppm - the exact image that was fed in (P6), for PSNR comparison
//
// Self-checks (printed as [PASS]/[FAIL] lines):
//   1. scan bytes produced at all
//   2. byte stuffing: every 0xFF data byte is followed by 0x00
//   3. scan_done pulses exactly once
//   4. no scan bytes emitted after scan_done
//   5. fifo_full_err never asserted
// After the sim, run:
//   python3 assemble_jpeg.py scan.bin W H out.jpg
//   python3 check_result.py input.ppm out.jpg W H
//
// Configuration: edit the parameters below (or override W/H/PATTERN from
// the simulator: iverilog -Ptb_jpeg_encoder_top.W=32 ...,
// xsim: xelab -generic_top W=32).
//
// Custom image mode (PATTERN = 2):
//   1. python3 img2hex.py your_photo.jpg 64 48      (needs Pillow)
//      -> writes image.hex (+ input.ppm reference) and prints the W/H to use
//   2. set W, H, PATTERN = 2, IMAGE_FILE = "image.hex" below
//   3. run the sim. The hex file must be in the simulator's working
//      directory (Vivado xsim: <project>.sim/sim_1/behav/xsim/) or give an
//      absolute path in IMAGE_FILE.
//
// Nothing in this file is meant for synthesis; simulation only.

module tb_jpeg_encoder_top;

    // ---------------- configuration ----------------
    parameter integer W         = 240;   // image width,  multiple of 8
    parameter integer H         = 240;   // image height, multiple of 8
    parameter integer PATTERN   = 2;    // 0 = colour blocks/gradient
                                        // 1 = gradient + high-freq texture
                                        // 2 = custom image from IMAGE_FILE
    // img2hex.py output, used when PATTERN = 2 (untyped parameter: iverilog
    // 11 has no `parameter string`; a plain parameter takes the string fine)
    parameter IMAGE_FILE = "image.hex";
    parameter integer MAX_CYCLES = 1000000;  // watchdog

    // ---------------- clock / reset ----------------
    reg clk = 1'b0;
    always #5 clk = ~clk;   // 100 MHz

    reg rst_n = 1'b0;

    // ---------------- DUT connections ----------------
    reg         in_valid = 1'b0;
    reg  [7:0]  r = 8'd0, g = 8'd0, b = 8'd0;

    wire        out_valid;
    wire [2:0]  out_nbytes;
    wire [31:0] out_data;
    wire        scan_done;
    wire        fifo_full_err;

    jpeg_encoder_top #(.W(W), .H(H)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .r(r), .g(g), .b(b),
        .out_valid(out_valid), .out_nbytes(out_nbytes),
        .out_data(out_data),
        .scan_done(scan_done), .fifo_full_err(fifo_full_err)
    );

    // ---------------- test image ----------------
    // Deterministic synthetic image, function of (x, y) only, so the PPM
    // written below matches exactly what the DUT is fed.
    function [23:0] make_pixel;
        input integer x;
        input integer y;
        integer bx, by, rr, gg, bb, h1, h2, h3;
        begin
            bx = x / 8;
            by = y / 8;
            if (PATTERN == 0) begin
                // colour blocks with a smooth gradient inside each block:
                // strong DC + low/mid AC content per 8x8 block
                rr = (bx*80 + x*7)        % 256;
                gg = (by*80 + y*11)       % 256;
                bb = ((bx+by)*40 + (x+y)*3) % 256;
            end else begin
                // gradient base + deterministic high-frequency texture:
                // forces dense AC coefficients, ZRL runs, 0xFF bytes
                h1 = (x*73856093) ^ (y*19349663);
                h1 = h1 ^ (h1 >>> 13);
                h2 = (x*83492791) ^ (y*2654435761);
                h2 = h2 ^ (h2 >>> 13);
                h3 = (x*19349663) ^ (y*73856093);
                h3 = h3 ^ (h3 >>> 13);
                rr = (x*4 + (h1 % 64) - 32);
                gg = (y*4 + (h2 % 64) - 32);
                bb = ((x+y)*2 + (h3 % 64) - 32);
                if (rr < 0) rr = 0;  if (rr > 255) rr = 255;
                if (gg < 0) gg = 0;  if (gg > 255) gg = 255;
                if (bb < 0) bb = 0;  if (bb > 255) bb = 255;
            end
            make_pixel = {rr[7:0], gg[7:0], bb[7:0]};
        end
    endfunction

    // ---------------- custom image (PATTERN == 2) ----------------
    // Packed RGB pixels from img2hex.py, raster order, one 24-bit value
    // per hex line. Loaded at time 0, before reset finishes.
    reg [23:0] img_mem [0:W*H-1];
    initial begin
        if (PATTERN == 2) begin
            $readmemh(IMAGE_FILE, img_mem);
            $display("[INFO] custom image mode: loaded %0d pixels from %s",
                     W*H, IMAGE_FILE);
        end
    end

    // ---------------- stimulus ----------------
    integer img_f;
    integer x, y;
    integer px;
    integer feed_cycles, total_cycles;
    integer cyc = 0;

    initial begin
        // open output files
        img_f = $fopen("input.ppm", "wb");
        if (img_f == 0) begin
            $display("[FAIL] could not open input.ppm for writing");
            $finish;
        end
        $fwrite(img_f, "P6\n%0d %0d\n255\n", W, H);

        // reset
        rst_n = 1'b0;
        repeat (20) @(posedge clk);
        rst_n <= 1'b1;
        repeat (5) @(posedge clk);

        // stream W*H pixels, raster order, 1 pixel/cycle
        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                if (PATTERN == 2)
                    px = img_mem[y*W + x];
                else
                    px = make_pixel(x, y);
                r        <= px[23:16];
                g        <= px[15:8];
                b        <= px[7:0];
                in_valid <= 1'b1;
                $fwrite(img_f, "%c%c%c", px[23:16], px[15:8], px[7:0]);
                @(posedge clk);
            end
        end
        in_valid <= 1'b0;
        $fclose(img_f);
        if (PATTERN == 2)
            $display("[INFO] fed %0d pixels (%0dx%0d, custom image %s)", W*H, W, H, IMAGE_FILE);
        else
            $display("[INFO] fed %0d pixels (%0dx%0d, pattern %0d)", W*H, W, H, PATTERN);

        // wait for the scan to finish (watchdog below catches a hang)
        wait (scan_done === 1'b1);
        repeat (20) @(posedge clk);

        check_and_finish;
    end

    // cycle counter + watchdog
    always @(posedge clk) begin
        cyc <= cyc + 1;
        if (cyc > MAX_CYCLES) begin
            $display("[FAIL] watchdog: no scan_done after %0d cycles", MAX_CYCLES);
            $display("TB_CHECKS: FAIL");
            $finish;
        end
    end

    // ---------------- capture + protocol checks ----------------
    integer scan_f;
    integer i;
    integer nbytes_total    = 0;
    integer nff             = 0;
    integer stuff_errors    = 0;
    integer done_count      = 0;
    integer bytes_after_done = 0;
    integer fifo_err_seen   = 0;
    reg [7:0] cur_byte;
    reg       prev_was_ff = 1'b0;
    reg       seen_done   = 1'b0;

    initial begin
        scan_f = $fopen("scan.bin", "wb");
        if (scan_f == 0) begin
            $display("[FAIL] could not open scan.bin for writing");
            $finish;
        end
    end

    always @(posedge clk) begin
        if (rst_n === 1'b1) begin
            if (fifo_full_err) fifo_err_seen = 1;
            if (scan_done) begin
                done_count = done_count + 1;
                seen_done  <= 1'b1;
            end
            if (out_valid) begin
                if (seen_done)  // scan_done already pulsed on an earlier cycle
                    bytes_after_done = bytes_after_done + out_nbytes;
                for (i = 0; i < out_nbytes; i = i + 1) begin
                    cur_byte = out_data[31 - i*8 -: 8];  // MSB byte first
                    $fwrite(scan_f, "%c", cur_byte);
                    if (prev_was_ff && (cur_byte !== 8'h00)) begin
                        stuff_errors = stuff_errors + 1;
                        $display("[FAIL] byte %0d: 0xFF followed by 0x%02x (missing stuffed 0x00)",
                                 nbytes_total, cur_byte);
                    end
                    if (cur_byte === 8'hFF) nff = nff + 1;
                    prev_was_ff  = (cur_byte === 8'hFF);
                    nbytes_total = nbytes_total + 1;
                end
            end
        end
    end

    // ---------------- summary ----------------
    integer errors;
    task check_and_finish;
        begin
            $fclose(scan_f);
            $display("----------------------------------------------------------");
            $display("TB RESULTS  (%0dx%0d, pattern %0d, %0d cycles)", W, H, PATTERN, cyc);

            errors = 0;

            if (nbytes_total > 0)
                $display("[PASS] scan bytes produced: %0d bytes", nbytes_total);
            else begin
                $display("[FAIL] no scan bytes produced");  errors = errors + 1;
            end

            if (stuff_errors == 0)
                $display("[PASS] byte stuffing: all %0d 0xFF data bytes followed by 0x00", nff);
            else begin
                $display("[FAIL] byte stuffing: %0d unstuffed 0xFF bytes", stuff_errors);
                errors = errors + stuff_errors;
            end

            if (done_count == 1)
                $display("[PASS] scan_done pulsed exactly once");
            else begin
                $display("[FAIL] scan_done pulsed %0d times (expected 1)", done_count);
                errors = errors + 1;
            end

            if (bytes_after_done == 0)
                $display("[PASS] no scan bytes after scan_done");
            else begin
                $display("[FAIL] %0d bytes emitted after scan_done", bytes_after_done);
                errors = errors + 1;
            end

            if (fifo_err_seen == 0)
                $display("[PASS] fifo_full_err never asserted");
            else begin
                $display("[FAIL] fifo_full_err asserted (token FIFO overflow)");
                errors = errors + 1;
            end

            if (errors == 0)
                $display("TB_CHECKS: ALL PASS");
            else
                $display("TB_CHECKS: FAIL (%0d error(s))", errors);
            $display("Next: python3 assemble_jpeg.py scan.bin %0d %0d out.jpg", W, H);
            $display("      python3 check_result.py input.ppm out.jpg %0d %0d", W, H);
            $display("----------------------------------------------------------");
            $finish;
        end
    endtask

endmodule