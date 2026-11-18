`timescale 1ns/1ps

// tb_jpeg_jfif_top.sv - end-to-end testbench for the complete JPEG top.
// Drives jpeg_encoder_jfif_top and writes the output byte stream directly
// to fpga.jpg (no host-side assemble_jpeg.py step is needed).
// A parallel jpeg_encoder_top instance captures the raw scan bytes for the
// byte-count and optional reference-flow checks.
//
// Configuration:
//   W/H must be multiples of 8. PATTERN=0 is flat gray; PATTERN=1 is a
//   deterministic gradient; PATTERN=2 loads packed RGB pixels from
//   IMAGE_FILE (one RRGGBB hex value per line, raster order).
//   Example for a custom image:
//     python3 img2hex.py photo.jpg 64 48 image.hex
//     Set W=64, H=48, PATTERN=2, IMAGE_FILE="image.hex" below.
//     Run the simulation from the directory containing image.hex.
//     fpga.jpg is the complete JPEG output from the RTL.
//
// Output files: fpga.jpg (complete JPEG), scan.bin (raw encoder scan),
// and input.ppm (exact RGB pixels fed to the encoder).
module tb_jpeg_jfif_top;
    parameter integer W = 240;
    parameter integer H = 240;
    parameter integer PATTERN = 2;    // 0=flat gray, 1=gradient, 2=custom image
    parameter IMAGE_FILE = "image.hex";
    parameter integer MAX_CYCLES = 2000000;

    reg clk = 1'b0;
    always #5 clk = ~clk;

    reg rst_n = 1'b0;
    reg in_valid = 1'b0;
    reg [7:0] r = 8'd0, g = 8'd0, b = 8'd0;

    // Full JPEG DUT
    wire        jfif_valid, jpg_done, jfif_err;
    wire [2:0]  jfif_nbytes;
    wire [31:0] jfif_data;

    jpeg_encoder_jfif_top #(.W(W), .H(H)) dut (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .r(r), .g(g), .b(b),
        .out_valid(jfif_valid), .out_nbytes(jfif_nbytes),
        .out_data(jfif_data), .jpg_done(jpg_done),
        .fifo_full_err(jfif_err)
    );

    // Raw-scan reference instance, fed the exact same pixels
    wire        ref_valid, ref_done, ref_err;
    wire [2:0]  ref_nbytes;
    wire [31:0] ref_data;

    jpeg_encoder_top #(.W(W), .H(H)) ref_enc (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .r(r), .g(g), .b(b),
        .out_valid(ref_valid), .out_nbytes(ref_nbytes),
        .out_data(ref_data), .scan_done(ref_done),
        .fifo_full_err(ref_err)
    );

    // Custom image memory, matching img2hex.py's RRGGBB raster format.
    reg [23:0] img_mem [0:W*H-1];
    integer load_i;
    initial begin
        if (PATTERN == 2) begin
            $readmemh(IMAGE_FILE, img_mem);
            $display("TB_INFO custom image: %0d pixels from %s (%0dx%0d)",
                     W*H, IMAGE_FILE, W, H);
        end
    end

    integer fjpg, fscan, fppm;
    integer jpg_bytes = 0;
    integer scan_bytes = 0;
    integer errors = 0;
    integer x, y, i, px;
    integer timeout;
    integer cyc = 0;
    integer rr, gg, bb;
    reg [23:0] pixel;

    task automatic write_bytes(input integer fd, input [31:0] data,
                               input [2:0] n);
        integer k;
        begin
            for (k = 0; k < n; k = k + 1)
                $fwrite(fd, "%c", data[8*(3-k) +: 8]);
        end
    endtask

    // Capture each output word MSB-first. The testbench writes the complete
    // JPEG produced by the full top, plus raw scan bytes from the reference.
    always @(posedge clk) begin
        if (jfif_valid) begin
            write_bytes(fjpg, jfif_data, jfif_nbytes);
            jpg_bytes = jpg_bytes + jfif_nbytes;
        end
        if (ref_valid) begin
            write_bytes(fscan, ref_data, ref_nbytes);
            scan_bytes = scan_bytes + ref_nbytes;
        end
        if (rst_n) cyc = cyc + 1;
    end

    initial begin
        fjpg = $fopen("fpga.jpg", "wb");
        fscan = $fopen("scan.bin", "wb");
        fppm = $fopen("input.ppm", "wb");
        if ((fjpg == 0) || (fscan == 0) || (fppm == 0)) begin
            $display("TB_CHECK output_files: FAIL (could not open output file)");
            $finish;
        end
        $fwrite(fppm, "P6\n%0d %0d\n255\n", W, H);

        if ((W <= 0) || (H <= 0) || ((W % 8) != 0) || ((H % 8) != 0)) begin
            $display("TB_CHECK dimensions: FAIL (W/H must be positive multiples of 8)");
            errors = errors + 1;
        end
        if ((PATTERN < 0) || (PATTERN > 2)) begin
            $display("TB_CHECK pattern: FAIL (PATTERN must be 0, 1, or 2)");
            errors = errors + 1;
        end

        in_valid = 1'b0;
        rst_n = 1'b0;
        repeat (10) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        repeat (2) @(negedge clk);

        // Feed exactly W*H pixels in raster order. Driving on the falling
        // edge leaves stable inputs for the DUT's rising-edge sampling.
        for (i = 0; i < W*H; i = i + 1) begin
            x = i % W;
            y = i / W;
            if (PATTERN == 2) begin
                pixel = img_mem[i];
            end else if (PATTERN == 0) begin
                pixel = 24'h808080;
            end else begin
                rr = (x*7 + y*3) & 255;
                gg = (x*2 + y*5) & 255;
                bb = (x*4 + y*11) & 255;
                pixel = {rr[7:0], gg[7:0], bb[7:0]};
            end
            @(negedge clk);
            r = pixel[23:16];
            g = pixel[15:8];
            b = pixel[7:0];
            in_valid = 1'b1;
            $fwrite(fppm, "%c%c%c", pixel[23:16], pixel[15:8], pixel[7:0]);
            @(posedge clk);
        end
        @(negedge clk);
        in_valid = 1'b0;
        $fclose(fppm);
        if (PATTERN == 2)
            $display("TB_INFO fed %0d custom pixels (%0dx%0d) from %s",
                     W*H, W, H, IMAGE_FILE);
        else
            $display("TB_INFO fed %0d pixels (%0dx%0d, pattern %0d)",
                     W*H, W, H, PATTERN);

        timeout = 0;
        while ((jpg_done !== 1'b1) && (timeout < MAX_CYCLES)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (jpg_done !== 1'b1) begin
            $display("TB_CHECK jpg_done: FAIL (timeout after %0d cycles)", timeout);
            errors = errors + 1;
        end else begin
            $display("TB_CHECK jpg_done: PASS");
        end

        // Allow the output capture process to observe the final registered
        // EOI word before closing the files.
        repeat (4) @(posedge clk);
        $fclose(fjpg);
        $fclose(fscan);

        $display("TB_INFO image=%0dx%0d pattern=%0d jpg_bytes=%0d scan_bytes=%0d",
                 W, H, PATTERN, jpg_bytes, scan_bytes);
        if (scan_bytes > 0) begin
            $display("TB_CHECK scan_bytes: PASS (%0d bytes)", scan_bytes);
        end else begin
            $display("TB_CHECK scan_bytes: FAIL (no scan bytes produced)");
            errors = errors + 1;
        end

        // The header is 623 bytes and EOI is 2 bytes.
        if (jpg_bytes == scan_bytes + 625) begin
            $display("TB_CHECK byte_count (header 623 + scan + EOI 2): PASS");
        end else begin
            $display("TB_CHECK byte_count: FAIL (got %0d, expected %0d)",
                     jpg_bytes, scan_bytes + 625);
            errors = errors + 1;
        end

        if (jfif_err || ref_err) begin
            $display("TB_CHECK fifo_full_err: FAIL");
            errors = errors + 1;
        end else begin
            $display("TB_CHECK fifo_full_err: PASS (no overflow)");
        end

        if (errors == 0)
            $display("TB_CHECKS ALL PASS");
        else
            $display("TB_CHECKS %0d FAILURES", errors);
        $display("TB_INFO complete JPEG: fpga.jpg; input reference: input.ppm");
        $finish;
    end

    // Watchdog catches a missing jpg_done instead of hanging indefinitely.
    always @(posedge clk) begin
        if (rst_n && (cyc > MAX_CYCLES)) begin
            $display("TB_CHECK watchdog: FAIL (no completion after %0d cycles)", MAX_CYCLES);
            $finish;
        end
    end
endmodule
