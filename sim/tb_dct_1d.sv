
`timescale 1ns/1ps

module tb_dct_1d_regression;

    logic clk = 0;
    logic rst_n = 0;
    logic in_valid = 0;
    logic [11:0] in_data = 0;

    logic out_valid;
    logic signed [13:0] out_data;

    integer expected [0:7];

    integer output_count = 0;
    integer error_count  = 0;
    integer test_count   = 0;

    integer test_errors_before;

    // --------------------------------------------------
    // DUT
    // --------------------------------------------------

    dct_1d #(
        .IS_ROW_PASS(1)
    ) dut (
        .clk       (clk),
        .rst_n     (rst_n),
        .in_valid  (in_valid),
        .in_data   (in_data),
        .out_valid (out_valid),
        .out_data  (out_data)
    );

    always #5 clk = ~clk;

    // --------------------------------------------------
    // Reference model
    //
    // Uses the fixed-point coefficients in dct_1d.sv.
    //
    // Output order:
    // F0, F2, F4, F6, F1, F3, F5, F7
    // --------------------------------------------------

    function automatic integer round8(
        input integer signed value
    );
        round8 = (value + 128) >>> 8;
    endfunction

    task automatic calculate_expected(
        input integer s0,
        input integer s1,
        input integer s2,
        input integer s3,
        input integer s4,
        input integer s5,
        input integer s6,
        input integer s7
    );

        integer signed x [0:7];

        integer signed p0, p1, p2, p3;
        integer signed d0, d1, d2, d3;

        integer signed f0, f2, f4, f6;
        integer signed f1, f3, f5, f7;

        begin

            // Level shift
            x[0] = s0 - 128;
            x[1] = s1 - 128;
            x[2] = s2 - 128;
            x[3] = s3 - 128;
            x[4] = s4 - 128;
            x[5] = s5 - 128;
            x[6] = s6 - 128;
            x[7] = s7 - 128;

            // Symmetric sums
            p3 = x[3] + x[4];
            p2 = x[2] + x[5];
            p1 = x[1] + x[6];
            p0 = x[0] + x[7];

            // Antisymmetric differences
            d3 = x[3] - x[4];
            d2 = x[2] - x[5];
            d1 = x[1] - x[6];
            d0 = x[0] - x[7];

            // Even frequencies
            f0 = round8(
                90 * (p3 + p2 + p1 + p0)
            );

            f2 = round8(
                -118*p3 - 49*p2 + 49*p1 + 118*p0
            );

            f4 = round8(
                90 * (p3 - p2 - p1 + p0)
            );

            f6 = round8(
                -49*p3 + 118*p2 - 118*p1 + 49*p0
            );

            // Odd frequencies
            f1 = round8(
                25*d3 + 71*d2 + 106*d1 + 125*d0
            );

            f3 = round8(
                -71*d3 - 125*d2 - 25*d1 + 106*d0
            );

            f5 = round8(
                106*d3 + 25*d2 - 125*d1 + 71*d0
            );

            f7 = round8(
                -125*d3 + 106*d2 - 71*d1 + 25*d0
            );

            // RTL output order
            expected[0] = f0;
            expected[1] = f2;
            expected[2] = f4;
            expected[3] = f6;
            expected[4] = f1;
            expected[5] = f3;
            expected[6] = f5;
            expected[7] = f7;

        end
    endtask

    // --------------------------------------------------
    // Output checker
    // --------------------------------------------------

    always @(posedge clk) begin

        if (rst_n && out_valid) begin

            if (output_count >= 8) begin

                $display("ERROR: Extra output received");
                error_count = error_count + 1;

            end
            else begin

                if ($signed(out_data) !== expected[output_count]) begin

                    $display(
                        "MISMATCH: Test=%0d Index=%0d Actual=%0d Expected=%0d",
                        test_count,
                        output_count,
                        $signed(out_data),
                        expected[output_count]
                    );

                    error_count = error_count + 1;

                end

                output_count = output_count + 1;

            end

        end

    end

    // --------------------------------------------------
    // Test task
    // Resets DUT between vectors so each test is isolated.
    // --------------------------------------------------

    task automatic run_vector(
        input string test_name,

        input integer s0,
        input integer s1,
        input integer s2,
        input integer s3,
        input integer s4,
        input integer s5,
        input integer s6,
        input integer s7
    );

        begin

            test_count = test_count + 1;

            test_errors_before = error_count;

            $display("");
            $display("======================================");
            $display("TEST %0d: %s", test_count, test_name);
            $display("======================================");

            // Calculate expected output
            calculate_expected(
                s0, s1, s2, s3,
                s4, s5, s6, s7
            );

            // Reset DUT
            @(negedge clk);

            rst_n    = 0;
            in_valid = 0;
            in_data  = 0;

            output_count = 0;

            repeat (3) @(negedge clk);

            rst_n = 1;

            // Send 8 samples
            for (integer i = 0; i < 8; i++) begin

                @(negedge clk);

                in_valid = 1;

                case (i)
                    0: in_data = s0;
                    1: in_data = s1;
                    2: in_data = s2;
                    3: in_data = s3;
                    4: in_data = s4;
                    5: in_data = s5;
                    6: in_data = s6;
                    7: in_data = s7;
                endcase

            end

            // Stop input
            @(negedge clk);

            in_valid = 0;
            in_data  = 0;

            // Allow pipeline to complete
            repeat (20) @(negedge clk);

            // Verify coefficient count
            if (output_count != 8) begin

                $display(
                    "ERROR: Expected 8 outputs, received %0d",
                    output_count
                );

                error_count = error_count + 1;

            end

            // Test summary
            if (error_count == test_errors_before)
                $display("TEST PASSED: %s", test_name);
            else
                $display("TEST FAILED: %s", test_name);

        end

    endtask

    // --------------------------------------------------
    // Main regression
    // --------------------------------------------------

    initial begin

        rst_n    = 0;
        in_valid = 0;
        in_data  = 0;

        repeat (4) @(negedge clk);

        // 1. Zero after level shift
        run_vector(
            "Zero input",
            128,128,128,128,128,128,128,128
        );

        // 2. Constant positive
        run_vector(
            "Constant 129",
            129,129,129,129,129,129,129,129
        );

        // 3. Constant maximum
        run_vector(
            "Constant 255",
            255,255,255,255,255,255,255,255
        );

        // 4. Constant minimum
        run_vector(
            "Constant 0",
            0,0,0,0,0,0,0,0
        );

        // 5. Impulse at first position
        run_vector(
            "Impulse at sample 0",
            255,128,128,128,128,128,128,128
        );

        // 6. Impulse at last position
        run_vector(
            "Impulse at sample 7",
            128,128,128,128,128,128,128,255
        );

        // 7. Alternating high-frequency pattern
        run_vector(
            "Alternating 255 and 128",
            255,128,255,128,255,128,255,128
        );

        // 8. Reverse alternating pattern
        run_vector(
            "Alternating 128 and 255",
            128,255,128,255,128,255,128,255
        );

        // 9. Ramp
        run_vector(
            "Ascending ramp",
            0,32,64,96,128,160,192,224
        );

        // 10. Descending ramp
        run_vector(
            "Descending ramp",
            224,192,160,128,96,64,32,0
        );

        // 11. Symmetric input
        run_vector(
            "Symmetric pattern",
            0,32,64,255,255,64,32,0
        );

        // 12. Antisymmetric input
        run_vector(
            "Antisymmetric pattern",
            0,32,64,255,0,191,160,128
        );

        // --------------------------------------------------
        // Randomized regression
        // --------------------------------------------------

        for (integer t = 0; t < 100; t++) begin

            run_vector(
                "Random vector",

                $urandom_range(0,255),
                $urandom_range(0,255),
                $urandom_range(0,255),
                $urandom_range(0,255),
                $urandom_range(0,255),
                $urandom_range(0,255),
                $urandom_range(0,255),
                $urandom_range(0,255)
            );

        end

        // --------------------------------------------------
        // Final report
        // --------------------------------------------------

        $display("");
        $display("======================================");
        $display("REGRESSION COMPLETE");
        $display("======================================");

        $display("Total tests  = %0d", test_count);
        $display("Total errors = %0d", error_count);

        if (error_count == 0)
            $display("ALL TESTS PASSED");
        else
            $display("REGRESSION FAILED");

        $finish;

    end

endmodule
