`timescale 1ns/1ps

// jpeg_encoder_jfif_top.sv - complete JPEG encoder with on-chip JFIF
// wrapping: RGB pixels in -> complete .jpg byte stream out.
//
// Wraps jpeg_encoder_top (pixel front end + entropy coder) with
// jfif_header (SOI/APP0/DQT/SOF0/DHT/SOS) and appends EOI after the scan.
// The output on out_data/out_nbytes/out_valid is byte-for-byte identical
// to feeding jpeg_encoder_top's scan output through assemble_jpeg.py.
// jpg_done pulses after the final EOI byte.
//
// W and H must be multiples of 8 and are written into the SOF0 header, so
// any image shape produces a valid, correctly-sized .jpg. Feed W*H pixels
// in raster order with in_valid - pixels may be fed immediately after
// reset; scan bytes produced while the header streams out are buffered in
// an internal FIFO (256 words = 1024 bytes, one 7-series BRAM; the header
// takes 156 cycles and the encoder emits at most one 32-bit word per
// cycle, so 156 words is the true high-water mark).
module jpeg_encoder_jfif_top #(
    parameter int W = 240,
    parameter int H = 240
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [7:0]  r, g, b,

    output logic        out_valid,
    output logic [2:0]  out_nbytes,
    output logic [31:0] out_data,
    output logic        jpg_done,
    output logic        fifo_full_err
);
    // ---------------- inner encoder (scan stream) ----------------
    logic        enc_valid, enc_done, enc_fifo_err;
    logic [2:0]  enc_nbytes;
    logic [31:0] enc_data;

    jpeg_encoder_top #(.W(W), .H(H)) u_enc (
        .clk(clk), .rst_n(rst_n),
        .in_valid(in_valid), .r(r), .g(g), .b(b),
        .out_valid(enc_valid), .out_nbytes(enc_nbytes),
        .out_data(enc_data), .scan_done(enc_done),
        .fifo_full_err(enc_fifo_err)
    );

    // ---------------- header generator ----------------
    logic        hdr_start, hdr_valid, hdr_done;
    logic [2:0]  hdr_nbytes;
    logic [31:0] hdr_data;

    jfif_header #(.IMG_W(W), .IMG_H(H)) u_hdr (
        .clk(clk), .rst_n(rst_n),
        .start(hdr_start),
        .out_valid(hdr_valid), .out_nbytes(hdr_nbytes),
        .out_data(hdr_data), .header_done(hdr_done)
    );

    // ---------------- scan FIFO (FWFT, distributed RAM) ----------------
    localparam int AW = 8;                 // 256 entries
    // FWFT async read maps to distributed (LUT) RAM, not BRAM.
    (* ram_style = "distributed" *) logic [34:0] fifo_mem [0:(1<<AW)-1]; // {nbytes[2:0], data[31:0]}
    logic [AW:0] wr_ptr, rd_ptr;
    logic        fifo_empty;

    assign fifo_empty = (wr_ptr == rd_ptr);
    wire   fifo_push  = enc_valid;
    wire   fifo_pop;

    // FIFO memory write in its own reset-free process so Vivado infers
    // distributed RAM instead of ~9k flip-flops.
    always_ff @(posedge clk) begin
        if (fifo_push)
            fifo_mem[wr_ptr[AW-1:0]] <= {enc_nbytes, enc_data};
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr <= '0;
            rd_ptr <= '0;
        end else begin
            if (fifo_push) begin
                wr_ptr <= wr_ptr + 1'b1;
            end
            if (fifo_pop)
                rd_ptr <= rd_ptr + 1'b1;
        end
    end

    // sticky overflow / inner-fifo error flag
    logic err_sticky;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) err_sticky <= 1'b0;
        else if (enc_fifo_err || (fifo_push && (wr_ptr - rd_ptr) == (1<<AW)))
            err_sticky <= 1'b1;
    end
    assign fifo_full_err = err_sticky;

    // ---------------- output FSM ----------------
    typedef enum logic [1:0] {S_HDR, S_SCAN, S_EOI, S_DONE} state_t;
    state_t state;
    logic   scan_done_seen;

    wire [34:0] fifo_head = fifo_mem[rd_ptr[AW-1:0]];
    assign fifo_pop = (state == S_SCAN) && !fifo_empty;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= S_HDR;
            hdr_start     <= 1'b0;
            scan_done_seen <= 1'b0;
            out_valid     <= 1'b0;
            out_nbytes    <= 3'd0;
            out_data      <= 32'd0;
            jpg_done      <= 1'b0;
        end else begin
            hdr_start <= 1'b0;
            jpg_done  <= 1'b0;
            if (enc_done) scan_done_seen <= 1'b1;

            case (state)
                S_HDR: begin
                    hdr_start <= 1'b1;   // held until the header engine accepts
                    if (hdr_valid) begin
                        // header engine started; stream its words through
                        hdr_start  <= 1'b0;
                        out_valid  <= 1'b1;
                        out_nbytes <= hdr_nbytes;
                        out_data   <= hdr_data;
                    end else if (!hdr_start) begin
                        out_valid <= 1'b0;
                    end
                    if (hdr_done) begin
                        state     <= S_SCAN;
                        out_valid <= 1'b0;
                    end
                end

                S_SCAN: begin
                    if (!fifo_empty) begin
                        out_valid  <= 1'b1;
                        out_nbytes <= fifo_head[34:32];
                        out_data   <= fifo_head[31:0];
                    end else begin
                        out_valid <= 1'b0;
                    end
                    if (scan_done_seen && fifo_empty && !enc_valid) begin
                        state     <= S_EOI;
                        out_valid <= 1'b0;
                    end
                end

                S_EOI: begin
                    out_valid  <= 1'b1;
                    out_nbytes <= 3'd2;
                    out_data   <= 32'hFFD90000;   // EOI marker, MSB first
                    state      <= S_DONE;
                end

                S_DONE: begin
                    out_valid <= 1'b0;
                    jpg_done  <= 1'b1;
                end
            endcase
        end
    end
endmodule
