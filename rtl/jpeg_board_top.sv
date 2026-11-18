`timescale 1ns/1ps

// jpeg_board_top.sv - Nexys 4 DDR board wrapper for jpeg_encoder_jfif_top.
//
// Host <-> board protocol over the FT2232 USB-UART (8N1):
//
//   Host -> FPGA:
//     "IMG"          3 magic bytes
//     W  (2 bytes, big-endian)   must match the compiled IMG_W parameter
//     H  (2 bytes, big-endian)   must match the compiled IMG_H parameter
//     W*H*3 RGB bytes            raster order, R then G then B per pixel
//
//   FPGA -> host (after encoding):
//     LEN (4 bytes, big-endian)  total .jpg byte count
//     LEN jpg bytes              complete JFIF file (SOI ... EOI)
//
// The encoder accepts pixels whenever in_valid pulses, so the slow UART
// just feeds pixels as bytes arrive. The encoder output cannot be stalled,
// so every output byte is queued in a BRAM FIFO before transmission.
// NOTE on sizing: the bit packer emits many 1-byte words (a 240x240
// quality-50 photo produced ~13k words for ~16.7 KB), so queueing raw
// 35-bit words would need one FIFO entry per BYTE in the worst case.
// Instead, output bytes are repacked into full 32-bit words here, so this
// 16384-deep FIFO holds a .jpg of up to 64 KB (16 BRAM36 tiles).
// Transmission starts only after jpg_done, when the total length is known.
//
// LEDs:  [0] receiving image   [1] encoding   [2] sending jpg
//        [3] done (jpg fully sent)   [15] error (bad header or FIFO overflow)
// Reset: CPU_RESETN pushbutton (active-low). One image per reset.
//
// Clocking: the 100 MHz board oscillator (clk100, pin E3) feeds an
// MMCME2_ADV that divides it to 50 MHz, and the ENTIRE design - UART,
// encoder, repacker, FIFOs - runs on that 50 MHz clock. The encoder's
// worst post-route path is ~18.2ns, which missed the 10ns period at
// 100 MHz (WNS -8.26ns, 1010 failing endpoints) but fits the 20ns
// period at 50 MHz with ~1.8ns margin. The UART baud is unchanged:
// CLKS_PER_BIT = 54 gives 925.9 kbaud from 50 MHz (target 921600,
// 0.47% error - fine for 8N1). Use 434 for 115200 baud operation.
// For simulation define SIM_BYPASS_MMCM: iverilog has no MMCM model, so
// the testbench drives clk100 at 50 MHz (20ns period) directly.
// v2 debug/fix: bytes_sent counts per byte (was per word at every byte,
// truncating the stream to 1/4 when jpg_len%16==0); byte mux rewritten as a
// fixed case statement; SW0/SW1 self-test modes; LED version mark.
// v3: reset RELEASE is now synchronized to clk50 (2-FF, async assert / sync
// release). Before this, rst_n rose asynchronously, and in SW0 self-test
// mode st_cnt could escape reset one ragged edge before fifo_wptr, so the
// first FIFO word held {04,05,06,07} instead of {00,01,02,03}. Also uses
// the ROM-based jfif_header (byte 3 of header words came out as 0x00 on
// hardware with the old per-byte case). LED[7:4]=1011.
module jpeg_board_top #(
    parameter int IMG_W        = 240,
    parameter int IMG_H        = 240,
    parameter int CLKS_PER_BIT = 54
) (
    input  logic        clk100,
    input  logic        cpu_resetn,
    input  logic        uart_rxd,
    output logic        uart_txd,
    input  logic [1:0]  sw,
    output logic [15:0] led
);
    // ------------------------------------------ clocking: 100 -> 50 MHz
    // Vivado auto-derives the 20ns generated clock on the MMCM output
    // from the 10ns create_clock on clk100 - no extra xdc entries and
    // no false paths are needed.
    logic clk50;
    logic mmcm_locked;
`ifdef SIM_BYPASS_MMCM
    // Simulation only: no MMCM model; the TB drives clk100 at 50 MHz.
    assign clk50       = clk100;
    assign mmcm_locked = 1'b1;
`else
    wire clk100_ibuf, clk50_unbuf, clkfb_unbuf, clkfb;
    IBUF u_ibuf_clk (.I(clk100), .O(clk100_ibuf));
    MMCME2_ADV #(
        .BANDWIDTH("OPTIMIZED"),
        .CLKIN1_PERIOD(10.0),          // 100 MHz board oscillator
        .DIVCLK_DIVIDE(1),
        .CLKFBOUT_MULT_F(10.000),      // VCO = 100 MHz * 10 = 1000 MHz
        .CLKFBOUT_PHASE(0.0),
        .CLKOUT0_DIVIDE_F(20.000),     // 1000 MHz / 20 = 50 MHz core clock
        .CLKOUT0_PHASE(0.0),
        .CLKOUT0_DUTY_CYCLE(0.5),
        .STARTUP_WAIT("FALSE")
    ) u_mmcm (
        .CLKIN1(clk100_ibuf),
        .CLKIN2(1'b0),
        .CLKINSEL(1'b1),
        .CLKFBIN(clkfb),
        .RST(~cpu_resetn),             // re-lock while the reset button is held
        .PWRDWN(1'b0),
        .CLKFBOUT(clkfb_unbuf),
        .CLKFBOUTB(),
        .CLKOUT0(clk50_unbuf),
        .CLKOUT0B(), .CLKOUT1(), .CLKOUT1B(), .CLKOUT2(), .CLKOUT2B(),
        .CLKOUT3(), .CLKOUT3B(), .CLKOUT4(), .CLKOUT5(), .CLKOUT6(),
        .LOCKED(mmcm_locked),
        .CLKINSTOPPED(), .CLKFBSTOPPED(),
        .PSCLK(1'b0), .PSEN(1'b0), .PSINCDEC(1'b0), .PSDONE(),
        .DCLK(1'b0), .DADDR(7'd0), .DI(16'd0), .DEN(1'b0), .DWE(1'b0),
        .DO(), .DRDY()
    );
    BUFG u_bufg_fb  (.I(clkfb_unbuf), .O(clkfb));
    BUFG u_bufg_clk (.I(clk50_unbuf), .O(clk50));
`endif

    // Hold the whole design in reset until the MMCM has locked, then
    // release SYNCHRONOUSLY to clk50: the raw release is asynchronous and
    // can pull registers out of reset on a ragged edge (recovery/removal
    // violation), which corrupted the SW0 self-test's first FIFO word.
    logic rst_n_async;
    assign rst_n_async = cpu_resetn & mmcm_locked;

    (* ASYNC_REG = "TRUE" *) logic [2:0] rst_sync;
    always_ff @(posedge clk50 or negedge rst_n_async) begin
        if (!rst_n_async) rst_sync <= 3'b000;
        else              rst_sync <= {rst_sync[1:0], 1'b1};
    end
    wire rst_n = rst_sync[2];

    // ---------------------------------------------------------------- UART
    logic       rx_valid;
    logic [7:0] rx_data;
    uart_rx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_rx (
        .clk(clk50), .rst_n(rst_n),
        .rxd(uart_rxd), .rx_valid(rx_valid), .rx_data(rx_data)
    );

    logic       tx_start, tx_busy;
    logic [7:0] tx_data;
    uart_tx #(.CLKS_PER_BIT(CLKS_PER_BIT)) u_tx (
        .clk(clk50), .rst_n(rst_n),
        .tx_start(tx_start), .tx_data(tx_data),
        .tx_busy(tx_busy), .txd(uart_txd)
    );

    // ------------------------------------------------- host header receive
    typedef enum logic [3:0] {
        R_M0, R_M1, R_M2, R_W0, R_W1, R_H0, R_H1, R_PIX, R_FIN, R_ERR
    } rstate_t;
    rstate_t rstate;

    logic [15:0] host_w, host_h;
    logic [31:0] pix_cnt;
    logic [1:0]  byte_phase;
    logic [7:0]  pix_r, pix_g, pix_b;
    logic        enc_in_valid;
    logic        hdr_err;

    localparam logic [31:0] NPIX = IMG_W * IMG_H;

    always_ff @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            rstate       <= R_M0;
            host_w       <= 16'd0;
            host_h       <= 16'd0;
            pix_cnt      <= 32'd0;
            byte_phase   <= 2'd0;
            pix_r        <= 8'd0;
            pix_g        <= 8'd0;
            pix_b        <= 8'd0;
            enc_in_valid <= 1'b0;
            hdr_err      <= 1'b0;
        end else begin
            enc_in_valid <= 1'b0;   // default: one-cycle pulse
            if (rx_valid) begin
                case (rstate)
                    R_M0: if (rx_data == 8'h49) rstate <= R_M1;                  // 'I'
                    R_M1: rstate <= (rx_data == 8'h4D) ? R_M2 :                // 'M'
                                    (rx_data == 8'h49) ? R_M1 : R_M0;
                    R_M2: rstate <= (rx_data == 8'h47) ? R_W0 :                // 'G'
                                    (rx_data == 8'h49) ? R_M1 : R_M0;
                    R_W0: begin host_w[15:8] <= rx_data; rstate <= R_W1; end
                    R_W1: begin host_w[7:0]  <= rx_data; rstate <= R_H0; end
                    R_H0: begin host_h[15:8] <= rx_data; rstate <= R_H1; end
                    R_H1: begin
                        host_h[7:0] <= rx_data;
                        if ((host_w == 16'(IMG_W)) &&
                            ({host_h[15:8], rx_data} == 16'(IMG_H))) begin
                            rstate     <= R_PIX;
                            pix_cnt    <= 32'd0;
                            byte_phase <= 2'd0;
                        end else begin
                            rstate  <= R_ERR;
                            hdr_err <= 1'b1;
                        end
                    end
                    R_PIX: begin
                        case (byte_phase)
                            2'd0: begin pix_r <= rx_data; byte_phase <= 2'd1; end
                            2'd1: begin pix_g <= rx_data; byte_phase <= 2'd2; end
                            default: begin
                                pix_b        <= rx_data;
                                byte_phase   <= 2'd0;
                                // pixel presented next cycle: r/g already
                                // registered, pix_b is registered here
                                enc_in_valid <= 1'b1;
                                if (pix_cnt == NPIX - 1)
                                    rstate <= R_FIN;
                                else
                                    pix_cnt <= pix_cnt + 1'b1;
                            end
                        endcase
                    end
                    R_FIN: ; // ignore any extra bytes
                    default: ; // R_ERR: stick until reset
                endcase
            end
        end
    end

    // ------------------------------------------------------------- encoder
    logic        enc_valid, enc_done, enc_fifo_err;
    logic [2:0]  enc_nbytes;
    logic [31:0] enc_data;

    jpeg_encoder_jfif_top #(.W(IMG_W), .H(IMG_H)) u_enc (
        .clk(clk50), .rst_n(rst_n),
        .in_valid(enc_in_valid), .r(pix_r), .g(pix_g), .b(pix_b),
        .out_valid(enc_valid), .out_nbytes(enc_nbytes), .out_data(enc_data),
        .jpg_done(enc_done), .fifo_full_err(enc_fifo_err)
    );

    // ------------------------------------- repack output bytes into words
    // enc_data carries 1-4 valid bytes, MSB-first. Append them below the
    // buffered bytes and emit one full 32-bit word whenever 4 bytes have
    // accumulated (at most one word per cycle: 3 buffered + 4 new < 8).
    // jpg_len counts exact bytes; on jpg_done a final partial word (if any)
    // is flushed - the TX side sends exactly jpg_len bytes, so the padding
    // bytes of that last word never leave the chip.
    logic [63:0] pack_buf;       // valid bytes are left-aligned (MSB side)
    logic [2:0]  pack_cnt;       // 0..3 valid bytes in pack_buf
    logic        pack_push;      // one-cycle FIFO write strobe
    logic [31:0] pack_word;
    logic        flush_pending;
    logic        all_pushed;     // every jpg byte is in the FIFO
    logic [31:0] jpg_len;

    // ---------------- self-test feed (SW1): 1-byte counter beats -----------
    // SW1 up at reset: the repacker is fed 1024 beats of one byte each
    // (byte value = beat index mod 256), bypassing the encoder entirely.
    logic [10:0] st_cnt;
    wire st0 = sw[0], st1 = sw[1];
    wire st0_fill = st0 && (st_cnt < 11'd256);    // SW0: fill FIFO directly
    wire st1_feed = st1 && (st_cnt < 11'd1024);   // SW1: feed the repacker

    always_ff @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) st_cnt <= 11'd0;
        else if (st0_fill || st1_feed) st_cnt <= st_cnt + 11'd1;
    end

    wire        penc_valid  = st1 ? st1_feed              : enc_valid;
    wire [2:0]  penc_nbytes = st1 ? 3'd1                  : enc_nbytes;
    wire [31:0] penc_data   = st1 ? {st_cnt[7:0], 24'd0}  : enc_data;
    wire        penc_done   = st1 ? (st_cnt == 11'd1024)  : enc_done;

    // append enc_data's top enc_nbytes bytes just below the buffered bytes:
    // byte i (at enc_data[31-8i -: 8]) moves to bits [63-8*(pack_cnt+i) -: 8]
    // (fixed shifts - no variable shifter)
    wire [63:0] enc_shifted = (pack_cnt == 2'd0) ? {penc_data, 32'd0} :
                              (pack_cnt == 2'd1) ? {8'd0, penc_data, 24'd0} :
                              (pack_cnt == 2'd2) ? {16'd0, penc_data, 16'd0} :
                                                   {24'd0, penc_data, 8'd0};
    wire [63:0] pack_next  = pack_buf | (penc_valid ? enc_shifted : 64'd0);
    wire [3:0]  pack_total = {1'b0, pack_cnt} + (penc_valid ? {1'b0, penc_nbytes} : 4'd0);

    always_ff @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            pack_buf      <= 64'd0;
            pack_cnt      <= 3'd0;
            pack_push     <= 1'b0;
            pack_word     <= 32'd0;
            flush_pending <= 1'b0;
            all_pushed    <= 1'b0;
            jpg_len       <= 32'd0;
        end else begin
            pack_push <= 1'b0;

            if (penc_valid) begin
                jpg_len <= jpg_len + 32'(penc_nbytes);
                if (pack_total >= 4'd4) begin
                    pack_push <= 1'b1;
                    pack_word <= pack_next[63:32];
                    pack_buf  <= pack_next << 32;
                    pack_cnt  <= 3'(pack_total - 4'd4);
                end else begin
                    pack_buf <= pack_next;
                    pack_cnt <= 3'(pack_total);
                end
            end

            if (penc_done) begin
                if (pack_cnt != 3'd0)
                    flush_pending <= 1'b1;
                else
                    all_pushed <= 1'b1;
            end

            if (flush_pending) begin
                // final partial word; low bytes are don't-care padding
                pack_push     <= 1'b1;
                pack_word     <= pack_buf[63:32];
                pack_buf      <= 64'd0;
                pack_cnt      <= 3'd0;
                flush_pending <= 1'b0;
                all_pushed    <= 1'b1;
            end
        end
    end

    // ------------------------------------------------- jpg capture FIFO
    // 16384 x 32 bit in block RAM = up to 64 KB of .jpg (16 BRAM36 tiles).
    localparam int FAW = 14;              // depth = 2**FAW = 16384 words
    (* ram_style = "block" *) logic [31:0] fifo_mem [0:(1<<FAW)-1];
    logic [FAW:0]   fifo_wptr, fifo_rptr;
    logic [31:0]    fifo_rd_data;
    logic           fifo_rd_en;
    logic           ovr_err;

    wire fifo_empty = (fifo_wptr == fifo_rptr);

    wire [7:0]  st_base = {st_cnt[5:0], 2'b00};   // stream byte N == N mod 256
    wire        fifo_we    = pack_push | st0_fill;
    wire [31:0] fifo_wdata  = st0_fill ? {st_base, st_base + 8'd1, st_base + 8'd2, st_base + 8'd3}
                                       : pack_word;

    always_ff @(posedge clk50) begin
        if (fifo_we)
            fifo_mem[fifo_wptr[FAW-1:0]] <= fifo_wdata;
        if (fifo_rd_en)
            fifo_rd_data <= fifo_mem[fifo_rptr[FAW-1:0]];
    end

    always_ff @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            fifo_wptr <= '0;
            fifo_rptr <= '0;
            ovr_err   <= 1'b0;
        end else begin
            if (pack_push | st0_fill) begin
                fifo_wptr <= fifo_wptr + 1'b1;
                if ((fifo_wptr - fifo_rptr) == (FAW+1)'(1 << FAW))
                    ovr_err <= 1'b1;
            end
            if (fifo_rd_en)
                fifo_rptr <= fifo_rptr + 1'b1;
            if (enc_fifo_err)
                ovr_err <= 1'b1;
        end
    end

    // --------------------------------------------------------- TX control
    // Sends the 4-byte big-endian length once all bytes are queued, then
    // drains the FIFO word by word (MSB-first) through uart_tx, sending
    // exactly jpg_len bytes in total.
    typedef enum logic [3:0] {
        T_WAIT_DONE, T_LEN_ISSUE, T_LEN_WAIT,
        T_RD, T_RD_LAT, T_RD_CAP,
        T_BYTE_ISSUE, T_BYTE_WAIT, T_FIN
    } tstate_t;
    tstate_t tstate;

    logic [1:0]  len_idx;
    logic [31:0] word_reg;
    logic [2:0]  word_nbytes;
    logic [2:0]  byte_idx;
    logic [31:0] bytes_sent;
    logic        tx_seen_busy;

    // SW0 self-test transmits 1024 pattern bytes; normal mode uses jpg_len.
    wire        st_done   = st0 && (st_cnt == 11'd256);
    wire [31:0] tx_len    = st0 ? 32'd1024 : jpg_len;
    wire        tx_ready  = all_pushed | st_done;

    wire [7:0] len_byte = (len_idx == 2'd0) ? tx_len[31:24] :
                          (len_idx == 2'd1) ? tx_len[23:16] :
                          (len_idx == 2'd2) ? tx_len[15:8]  : tx_len[7:0];

    wire [31:0] bytes_left = tx_len - bytes_sent;

    always_ff @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            tstate       <= T_WAIT_DONE;
            len_idx      <= 2'd0;
            word_reg     <= 32'd0;
            word_nbytes  <= 3'd0;
            byte_idx     <= 3'd0;
            bytes_sent   <= 32'd0;
            tx_start     <= 1'b0;
            tx_data      <= 8'd0;
            fifo_rd_en   <= 1'b0;
            tx_seen_busy <= 1'b0;
        end else begin
            tx_start   <= 1'b0;   // default: one-cycle pulses
            fifo_rd_en <= 1'b0;

            case (tstate)
                T_WAIT_DONE: begin
                    if (tx_ready) begin
                        len_idx <= 2'd0;
                        tstate  <= T_LEN_ISSUE;
                    end
                end

                T_LEN_ISSUE: begin
                    tx_data      <= len_byte;
                    tx_start     <= 1'b1;
                    tx_seen_busy <= 1'b0;
                    tstate       <= T_LEN_WAIT;
                end

                T_LEN_WAIT: begin
                    if (tx_busy) tx_seen_busy <= 1'b1;
                    if (tx_seen_busy && !tx_busy) begin
                        if (len_idx == 2'd3) begin
                            tstate <= T_RD;
                        end else begin
                            len_idx <= len_idx + 1'b1;
                            tstate  <= T_LEN_ISSUE;
                        end
                    end
                end

                T_RD: begin
                    if (bytes_sent == tx_len || fifo_empty) begin
                        tstate <= T_FIN;
                    end else begin
                        fifo_rd_en <= 1'b1;
                        tstate     <= T_RD_LAT;
                    end
                end

                T_RD_LAT: tstate <= T_RD_CAP;   // BRAM read latency

                T_RD_CAP: begin
                    word_reg    <= fifo_rd_data;
                    word_nbytes <= (bytes_left >= 32'd4) ? 3'd4 : 3'(bytes_left);
                    byte_idx    <= 3'd0;
                    tstate      <= T_BYTE_ISSUE;
                end

                T_BYTE_ISSUE: begin
                    case (byte_idx[1:0])
                        2'd0:    tx_data <= word_reg[31:24];
                        2'd1:    tx_data <= word_reg[23:16];
                        2'd2:    tx_data <= word_reg[15:8];
                        default: tx_data <= word_reg[7:0];
                    endcase
                    tx_start     <= 1'b1;
                    tx_seen_busy <= 1'b0;
                    tstate       <= T_BYTE_WAIT;
                end

                T_BYTE_WAIT: begin
                    if (tx_busy) tx_seen_busy <= 1'b1;
                    if (tx_seen_busy && !tx_busy) begin
                        bytes_sent <= bytes_sent + 32'd1;   // one per BYTE
                        if (byte_idx == word_nbytes - 3'd1) begin
                            tstate <= T_RD;
                        end else begin
                            byte_idx <= byte_idx + 1'b1;
                            tstate   <= T_BYTE_ISSUE;
                        end
                    end
                end

                default: tstate <= tstate;   // T_FIN: hold until reset
            endcase
        end
    end

    // ---------------------------------------------------------------- LEDs
    logic busy_tx, done_all, err_any;
    assign busy_tx  = (tstate != T_WAIT_DONE) && (tstate != T_FIN);
    assign done_all = (tstate == T_FIN);
    assign err_any  = hdr_err || ovr_err;

    assign led[0]    = (rstate != R_M0) && (rstate != R_FIN) && (rstate != R_ERR);
    assign led[1]    = (rstate == R_FIN) && (tstate == T_WAIT_DONE);
    assign led[2]    = busy_tx;
    assign led[3]    = done_all;
    assign led[14:8] = 7'd0;
    assign led[7:4]  = 4'b1011;   // v3 marker: ON/OFF/ON/ON
    assign led[15]   = err_any;

    // tie off unused signals
    logic unused;
    assign unused = &{1'b0, pix_cnt[0], byte_phase[0], host_w[0], host_h[0]};
endmodule