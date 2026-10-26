`timescale 1ns/1ps
// Streams the ROM image through the RGB->YCbCr converter.
// Pulse `start` to begin; `frame_done` pulses when the last address has been issued.

module image_source_top #(
    parameter int W = 240,
    parameter int H = 240
) (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       start,
    output logic       out_valid,
    output logic [7:0] y, cb, cr,
    output logic       frame_done
);
    localparam int N = W * H;

    // ---- Address counter ----
    logic [$clog2(N)-1:0] addr;
    logic                 running;
    logic                 rd_valid;   // addr was valid last cycle -> pixel is valid now

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            addr       <= '0;
            running    <= 1'b0;
            rd_valid   <= 1'b0;
            frame_done <= 1'b0;
        end else begin
            frame_done <= 1'b0;
            rd_valid   <= running;    // matches 1-cycle BRAM read latency

            if (start && !running) begin
                running <= 1'b1;
                addr    <= '0;
            end else if (running) begin
                if (addr == N-1) begin
                    running    <= 1'b0;
                    frame_done <= 1'b1;
                end else begin
                    addr <= addr + 1'b1;
                end
            end
        end
    end

    // ---- ROM ----
    logic [23:0] pixel;

    image_rom #(.W(W), .H(H)) u_rom (
        .clk  (clk),
        .addr (addr),
        .pixel(pixel)
    );

    // ---- Split pixel into R, G, B ----
    logic [7:0] r, g, b;
    assign r = pixel[23:16];
    assign g = pixel[15:8];
    assign b = pixel[7:0];

    // ---- Color conversion ----
    rgb_to_ycbcr u_cc (
        .clk      (clk),
        .rst_n    (rst_n),
        .in_valid (rd_valid),
        .r        (r),
        .g        (g),
        .b        (b),
        .out_valid(out_valid),
        .y        (y),
        .cb       (cb),
        .cr       (cr)
    );
endmodule
