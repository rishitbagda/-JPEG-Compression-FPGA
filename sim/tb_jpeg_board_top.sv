`timescale 1ns/1ps

// tb_jpeg_board_top.sv - full board-chain testbench:
//   UART bytes in ("IMG" + W + H + RGB pixels, bit-banged at CLKS_PER_BIT)
//   -> jpeg_board_top (uart_rx, protocol FSM, jpeg_encoder_jfif_top,
//      capture FIFO, uart_tx)
//   -> UART bytes out (4-byte big-endian length + .jpg), decoded and
//      written to board_fpga.jpg.
//
// Uses CLKS_PER_BIT=4 so the 240x240 image transfer simulates in a
// reasonable number of cycles (the UART logic is identical at any
// CLKS_PER_BIT; only the divider changes).
//
// Clocking: the DUT is compiled with -DSIM_BYPASS_MMCM, which bypasses
// the 100->50 MHz MMCME2_ADV (iverilog has no model for it). The whole
// design then runs straight off the clk100 input, so this TB drives it
// at 50 MHz (20 ns period) - the frequency the real board core runs at.
//
// Inputs:  image.hex (RRGGBB per line, W*H lines, from img2hex.py)
// Outputs: board_fpga.jpg (received jpg), plus TB_CHECK lines.
module tb_jpeg_board_top;
    parameter integer W = 240;
    parameter integer H = 240;
    parameter integer CPB = 4;               // CLKS_PER_BIT for the sim
    parameter IMAGE_FILE = "image.hex";
    parameter integer MAX_CYCLES = 12000000;

    reg clk = 1'b0;
    always #10 clk = ~clk;   // 50 MHz core clock (MMCM bypassed in sim)

    reg  cpu_resetn = 1'b0;
    reg  rxd_drive  = 1'b1;
    wire txd_wire;
    wire [15:0] led;

    jpeg_board_top #(.IMG_W(W), .IMG_H(H), .CLKS_PER_BIT(CPB)) dut (
        .clk100(clk), .cpu_resetn(cpu_resetn),
        .uart_rxd(rxd_drive), .uart_txd(txd_wire), .led(led)
    );

    // ---------------- image ----------------
    reg [23:0] img_mem [0:W*H-1];
    initial $readmemh(IMAGE_FILE, img_mem);

    // ---------------- UART receive capture (FPGA -> host) ----------------
    reg [7:0] rx_mem [0:400000-1];
    integer rx_count = 0;
    integer k;
    reg [7:0] cap_byte;
    initial begin
        forever begin
            @(negedge txd_wire);                 // start bit begins
            repeat (CPB/2) @(negedge clk);       // middle of start bit
            for (k = 0; k < 8; k = k + 1) begin
                repeat (CPB) @(negedge clk);     // middle of data bit k
                cap_byte[k] = txd_wire;
            end
            rx_mem[rx_count] = cap_byte;
            rx_count = rx_count + 1;
        end
    end

    // ---------------- UART transmit (host -> FPGA) ----------------
    task uart_send_byte(input [7:0] d);
        integer j;
        begin
            rxd_drive = 1'b0;                       // start bit
            repeat (CPB) @(negedge clk);
            for (j = 0; j < 8; j = j + 1) begin
                rxd_drive = d[j];                   // LSB first
                repeat (CPB) @(negedge clk);
            end
            rxd_drive = 1'b1;                       // stop bit
            repeat (CPB) @(negedge clk);
        end
    endtask

    integer i;
    integer jpg_len, got, errors, timeout;
    integer fout;
    integer cyc = 0;

    always @(posedge clk) if (cpu_resetn) cyc = cyc + 1;

    initial begin
        errors = 0;
        // reset
        cpu_resetn = 1'b0;
        repeat (20) @(negedge clk);
        cpu_resetn = 1'b1;
        repeat (20) @(negedge clk);

        // header: "IMG" + W + H (big-endian)
        uart_send_byte(8'h49);  // I
        uart_send_byte(8'h4D);  // M
        uart_send_byte(8'h47);  // G
        uart_send_byte(8'((W >> 8) & 255));
        uart_send_byte(8'(W & 255));
        uart_send_byte(8'((H >> 8) & 255));
        uart_send_byte(8'(H & 255));

        // pixels, raster order, R G B per pixel
        for (i = 0; i < W*H; i = i + 1) begin
            uart_send_byte(img_mem[i][23:16]);
            uart_send_byte(img_mem[i][15:8]);
            uart_send_byte(img_mem[i][7:0]);
        end
        $display("TB_INFO sent IMG header + %0d RGB bytes (%0dx%0d) at CLKS_PER_BIT=%0d",
                 W*H*3, W, H, CPB);

        // wait for 4-byte length prefix
        timeout = 0;
        while ((rx_count < 4) && (timeout < MAX_CYCLES)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        if (rx_count < 4) begin
            $display("TB_CHECK length_prefix: FAIL (no reply, timeout)");
            $display("TB_CHECKS %0d FAILURES", 1);
            $finish;
        end
        jpg_len = {rx_mem[0], rx_mem[1], rx_mem[2], rx_mem[3]};
        $display("TB_INFO FPGA reports jpg_len = %0d bytes", jpg_len);
        if (jpg_len > 0 && jpg_len < 400000 - 4) begin
            $display("TB_CHECK length_prefix: PASS (%0d bytes announced)", jpg_len);
        end else begin
            $display("TB_CHECK length_prefix: FAIL (implausible %0d)", jpg_len);
            errors = errors + 1;
        end

        // wait for the whole jpg
        timeout = 0;
        while ((rx_count < jpg_len + 4) && (timeout < MAX_CYCLES)) begin
            @(posedge clk);
            timeout = timeout + 1;
        end
        got = rx_count - 4;
        if (got == jpg_len) begin
            $display("TB_CHECK byte_count: PASS (%0d of %0d jpg bytes received)", got, jpg_len);
        end else begin
            $display("TB_CHECK byte_count: FAIL (got %0d of %0d)", got, jpg_len);
            errors = errors + 1;
        end

        // write board_fpga.jpg (bytes after the 4-byte prefix)
        fout = $fopen("board_fpga.jpg", "wb");
        for (i = 0; i < jpg_len; i = i + 1)
            $fwrite(fout, "%c", rx_mem[4 + i]);
        $fclose(fout);

        // SOI / EOI markers
        if (rx_mem[4] == 8'hFF && rx_mem[5] == 8'hD8)
            $display("TB_CHECK soi_marker: PASS");
        else begin
            $display("TB_CHECK soi_marker: FAIL (got %02x %02x)", rx_mem[4], rx_mem[5]);
            errors = errors + 1;
        end
        if (rx_mem[4 + jpg_len - 2] == 8'hFF && rx_mem[4 + jpg_len - 1] == 8'hD9)
            $display("TB_CHECK eoi_marker: PASS");
        else begin
            $display("TB_CHECK eoi_marker: FAIL");
            errors = errors + 1;
        end

        // no error LED
        if (led[15] === 1'b0)
            $display("TB_CHECK error_led: PASS (no FIFO overflow / header error)");
        else begin
            $display("TB_CHECK error_led: FAIL");
            errors = errors + 1;
        end

        if (errors == 0)
            $display("TB_CHECKS ALL PASS");
        else
            $display("TB_CHECKS %0d FAILURES", errors);
        $display("TB_INFO received JPEG: board_fpga.jpg (%0d bytes)", jpg_len);
        $finish;
    end

    // watchdog
    always @(posedge clk) begin
        if (cpu_resetn && (cyc > MAX_CYCLES)) begin
            $display("TB_CHECK watchdog: FAIL (no completion after %0d cycles)", MAX_CYCLES);
            $finish;
        end
    end
endmodule
