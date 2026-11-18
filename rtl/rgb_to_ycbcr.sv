`timescale 1ns/1ps

module rgb_to_ycbcr (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       in_valid,
    input  logic [7:0] r, g, b,
    output logic       out_valid,
    output logic [7:0] y, cb, cr
);
    logic signed [17:0] y_acc, cb_acc, cr_acc;
    logic               v1;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            y_acc     <= 18'sd0;
            cb_acc    <= 18'sd0;
            cr_acc    <= 18'sd0;
            y         <= 8'd0;
            cb        <= 8'd0;
            cr        <= 8'd0;
            v1        <= 1'b0;
            out_valid <= 1'b0;
        end else begin
            y_acc  <=  18'sd77  * $signed({1'b0, r}) + 18'sd150 * $signed({1'b0, g}) + 18'sd29  * $signed({1'b0, b});
            cb_acc <= -18'sd43  * $signed({1'b0, r}) - 18'sd85  * $signed({1'b0, g}) + 18'sd128 * $signed({1'b0, b});
            cr_acc <=  18'sd128 * $signed({1'b0, r}) - 18'sd107 * $signed({1'b0, g}) - 18'sd21  * $signed({1'b0, b});

            y  <= y_acc[15:8];
            cb <= 8'((cb_acc >>> 8) + 18'sd128);
            cr <= 8'((cr_acc >>> 8) + 18'sd128);

            v1        <= in_valid;
            out_valid <= v1;
        end
    end
endmodule