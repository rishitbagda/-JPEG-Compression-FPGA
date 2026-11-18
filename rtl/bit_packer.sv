`timescale 1ns/1ps

// Bit packer + byte stuffer: variable-length bit segments -> JPEG scan bytes.
// Accepts up to 27 bits per cycle (16-bit Huffman code + 11 amplitude bits).
// Emits up to 4 bytes per cycle on out_data (MSB-first, out_nbytes valid).
// A 0x00 is stuffed after every 0xFF data byte (never after markers: this
// block only handles scan data). On in_flush (with the final token) the
// remaining bits are padded with 1s to the byte boundary; out_done pulses
// when the last byte has left.
module bit_packer (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic        in_flush,
    input  logic [26:0] in_bits,
    input  logic [5:0]  in_nbits,
    output logic        out_valid,
    output logic [2:0]  out_nbytes,
    output logic [31:0] out_data,
    output logic        out_done
);
    logic [63:0] acc;            // queued bits, oldest at LSB end
    logic [6:0]  cnt;            // number of valid bits in acc
    logic        stuff_pending;  // emit a stuffed 0x00 before more data
    logic        flushing;

    // ---- combinational drain + append ----
    logic [63:0] acc_d;
    logic [6:0]  cnt_d;
    logic        stuff_d;
    logic [3:0]  nbytes_d;
    logic [31:0] data_d;
    logic [7:0]  b;

    always_comb begin
        acc_d     = acc;
        cnt_d     = cnt;
        stuff_d   = stuff_pending;
        nbytes_d  = 4'd0;
        data_d    = 32'd0;
        b         = 8'd0;

        // drain whole bytes from the TOP (oldest bits), max 4 per cycle,
        // stuffing 0x00 after every 0xFF data byte
        if (stuff_pending) begin
            data_d[31:24] = 8'h00;
            nbytes_d      = 4'd1;
            stuff_d       = 1'b0;
        end
        // fixed 4-iteration loop: Vivado cannot statically unroll a
        // data-dependent while condition. 4 iterations is the true bound
        // (nbytes_d < 4 caps the drain), and once the guard fails it stays
        // false for the remaining iterations, so behavior is identical.
        for (int i = 0; i < 4; i++) begin
            if (cnt_d >= 7'd8 && nbytes_d < 4'd4) begin
                b     = 8'(acc_d >> (cnt_d - 7'd8));
                acc_d = acc_d & ((64'd1 << (cnt_d - 7'd8)) - 64'd1);
                cnt_d = cnt_d - 7'd8;
                data_d = data_d | (32'(b) << (8 * (3 - nbytes_d)));
                nbytes_d = nbytes_d + 4'd1;
                if (b == 8'hFF) begin
                    if (nbytes_d < 4'd4) begin
                        data_d = data_d | (32'(8'h00) << (8 * (3 - nbytes_d)));
                        nbytes_d = nbytes_d + 4'd1;
                    end else begin
                        stuff_d = 1'b1;
                    end
                end
            end
        end

        // append new bits below the queued ones (oldest bits stay on top)
        if (in_valid) begin
            acc_d = (acc_d << 7'(in_nbits)) | 64'(in_bits);
            cnt_d = cnt_d + 7'(in_nbits);
        end

        // pad with 1s on flush, after appending the final token
        if (in_valid && in_flush) begin : flush_pad_blk
            logic [6:0] pad;
            pad = (7'(8) - (cnt_d % 7'(8))) % 7'(8);
            acc_d = (acc_d << pad) | ((64'd1 << pad) - 64'd1);
            cnt_d = cnt_d + pad;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc           <= 64'd0;
            cnt           <= 7'd0;
            stuff_pending <= 1'b0;
            flushing      <= 1'b0;
            out_valid     <= 1'b0;
            out_nbytes    <= 3'd0;
            out_data      <= 32'd0;
            out_done      <= 1'b0;
        end else begin
            if (in_valid && in_flush)
                flushing <= 1'b1;

            acc           <= acc_d;
            cnt           <= cnt_d;
            stuff_pending <= stuff_d;

            out_valid  <= (nbytes_d != 4'd0);
            out_nbytes <= 3'(nbytes_d);
            out_data   <= data_d;

            // done: single-cycle pulse when the flush byte(s) have drained
            // and nothing is left; clear flushing in the same cycle so the
            // pulse is exactly one clock wide
            if (flushing && (cnt_d == 7'd0) && !stuff_d && !in_valid) begin
                out_done <= 1'b1;
                flushing <= 1'b0;
            end else begin
                out_done <= 1'b0;
            end
        end
    end
endmodule