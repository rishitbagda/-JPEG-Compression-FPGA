
`timescale 1ns/1ps
// Self-checking testbench: compares every output pixel against expected.hex.
module tb;
    localparam int W = 240, H = 240, N = W * H;
 
    logic       clk = 0, rst_n = 0, start = 0;
    logic       out_valid, frame_done;
    logic [7:0] y, cb, cr;
 
    always #5 clk = ~clk;   // 100 MHz
 
    image_source_top #(.W(W), .H(H)) dut (.*);
 
    logic [23:0] expected [0:N-1];
    initial $readmemh("expected.hex", expected);
 
    int count  = 0;
    int errors = 0;
 
    always @(posedge clk) begin
        if (out_valid && count < N) begin
            if ({y, cb, cr} !== expected[count]) begin
                errors++;
                if (errors <= 10)
                    $display("MISMATCH pixel %0d: got %02x%02x%02x expected %06x",
                             count, y, cb, cr, expected[count]);
            end
            count++;
        end
    end
 
    initial begin
        #20 rst_n = 1;
        #20 start = 1;
        #10 start = 0;
        wait (frame_done);
        repeat (5) @(posedge clk);   // let the pipeline drain
        $display("Pixels checked: %0d / %0d", count, N);
        $display("Errors        : %0d", errors);
        if (count == N && errors == 0) $display("PASS");
        else                           $display("FAIL");
        $finish;
    end
endmodule