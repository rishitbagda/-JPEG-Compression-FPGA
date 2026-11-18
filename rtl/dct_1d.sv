`timescale 1ns/1ps

module dct_1d #(
    parameter bit IS_ROW_PASS = 1 
) (
    input  logic               clk,
    input  logic               rst_n,
    input  logic               in_valid,
    input  logic [11:0]        in_data,
    
    output logic               out_valid,
    output logic signed [13:0] out_data 
);
    // 9-bit scaled cosine constants: c_k' = round(0.5 * cos(k*pi/16) * 2^8)
    localparam signed [8:0] C1 = 9'sd125; 
    localparam signed [8:0] C2 = 9'sd118;
    localparam signed [8:0] C3 = 9'sd106;
    localparam signed [8:0] C4 = 9'sd90;
    localparam signed [8:0] C5 = 9'sd71;
    localparam signed [8:0] C6 = 9'sd49;
    localparam signed [8:0] C7 = 9'sd25;

    // Level-shift unsigned 8-bit pixels by -128 on Row Pass; sign-extend 12-bit inputs on Col Pass
    wire signed [12:0] x_in = IS_ROW_PASS ? ($signed({1'b0, in_data[7:0]}) - 13'sd128)
                                          : $signed({in_data[11], in_data});

    // 4-entry Fabric RAM for first 4 samples of each 8-sample vector (Fig. 2)
    logic signed [12:0] fabric_ram [0:3];
    logic [2:0]         in_idx;

    // Read in reverse order (3, 2, 1, 0) as samples 4, 5, 6, 7 arrive
    wire [1:0]         ram_rd_addr = 2'd3 - in_idx[1:0];
    wire signed [12:0] ram_out     = fabric_ram[ram_rd_addr];

    // Single Adder & Subtractor (Fig. 2)
    wire signed [13:0] add_out = ram_out + x_in;
    wire signed [13:0] sub_out = ram_out - x_in;

    // 4-stage delay shift register for differences (4 dark boxes in Fig. 2)
    logic signed [13:0] d_pipe [0:3];

    // Control phases for the 4 MAC units
    wire        even_phase = in_valid && in_idx[2]; // Active during samples 4, 5, 6, 7
    logic       odd_active;
    logic [1:0] odd_step;

    wire        mac_en   = even_phase || odd_active;
    wire [2:0]  rom_addr = even_phase ? {1'b0, in_idx[1:0]} : {1'b1, odd_step};
    wire signed [13:0] mac_in = even_phase ? add_out : d_pipe[3];

    // Coefficient RAM lookup (Fig. 2)
    logic signed [8:0] coeff [0:3];
    always_comb begin
        case (rom_addr)
            // Even frequency steps (s[3], s[2], s[1], s[0]) -> F[0], F[2], F[4], F[6]
            3'd0: begin coeff[0] =  C4; coeff[1] = -C2; coeff[2] =  C4; coeff[3] = -C6; end
            3'd1: begin coeff[0] =  C4; coeff[1] = -C6; coeff[2] = -C4; coeff[3] =  C2; end
            3'd2: begin coeff[0] =  C4; coeff[1] =  C6; coeff[2] = -C4; coeff[3] = -C2; end
            3'd3: begin coeff[0] =  C4; coeff[1] =  C2; coeff[2] =  C4; coeff[3] =  C6; end
            // Odd frequency steps (d[3], d[2], d[1], d[0]) -> F[1], F[3], F[5], F[7]
            3'd4: begin coeff[0] =  C7; coeff[1] = -C5; coeff[2] =  C3; coeff[3] = -C1; end
            3'd5: begin coeff[0] =  C5; coeff[1] = -C1; coeff[2] =  C7; coeff[3] =  C3; end
            3'd6: begin coeff[0] =  C3; coeff[1] = -C7; coeff[2] = -C1; coeff[3] = -C5; end
            3'd7: begin coeff[0] =  C1; coeff[1] =  C3; coeff[2] =  C5; coeff[3] =  C7; end
        endcase
    end

    // 4 Parallel MAC Accumulators + Combinational Next-Accumulate
    logic signed [23:0] acc      [0:3];
    logic signed [23:0] mac_next [0:3];
    wire                mac_init = (rom_addr[1:0] == 2'd0); // Reset every 4 cycles with +128 rounding offset

    always_comb begin
        for (int m = 0; m < 4; m++) begin
            mac_next[m] = (mac_init ? 24'sd128 : acc[m]) + (coeff[m] * mac_in);
        end
    end

    // Truncated & rounded MAC outputs (12-bit for Row Pass, 14-bit for Col Pass)
    logic signed [13:0] trunc_out [0:3];
    always_comb begin
        for (int m = 0; m < 4; m++) begin
            if (IS_ROW_PASS)
                trunc_out[m] = $signed({{2{mac_next[m][19]}}, mac_next[m][19:8]});
            else
                trunc_out[m] = $signed(mac_next[m][21:8]);
        end
    end

    // 4-Stage Output Shift Register (bottom of Fig. 2)
    logic signed [13:0] out_sr [0:2];
    logic [1:0]         out_cnt;
    wire                load_sr = mac_en && (rom_addr[1:0] == 2'd3);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            in_idx     <= 3'd0;
            odd_active <= 1'b0;
            odd_step   <= 2'd0;
            out_cnt    <= 2'd0;
            out_valid  <= 1'b0;
            out_data   <= 14'sd0;
            for (int i = 0; i < 4; i++) begin
                fabric_ram[i] <= 13'sd0;
                d_pipe[i]     <= 14'sd0;
                acc[i]        <= 24'sd0;
            end
            for (int i = 0; i < 3; i++) begin
                out_sr[i] <= 14'sd0;
            end
        end else begin
            // 1. Fabric RAM Write & Sample Counter
            if (in_valid) begin
                if (!in_idx[2]) begin
                    fabric_ram[in_idx[1:0]] <= x_in;
                end
                in_idx <= in_idx + 3'd1;
            end

            // 2. 4-Stage Difference Delay Line
            d_pipe[0] <= sub_out;
            d_pipe[1] <= d_pipe[0];
            d_pipe[2] <= d_pipe[1];
            d_pipe[3] <= d_pipe[2];

            // 3. Odd-Frequency Phase Sequencer
            if (in_valid && (in_idx == 3'd7)) begin
                odd_active <= 1'b1;
                odd_step   <= 2'd0;
            end else if (odd_active) begin
                if (odd_step == 2'd3) begin
                    odd_active <= 1'b0;
                    odd_step   <= 2'd0;
                end else begin
                    odd_step <= odd_step + 2'd1;
                end
            end

            // 4. Update 4 MAC Accumulators
            if (mac_en) begin
                for (int m = 0; m < 4; m++) begin
                    acc[m] <= mac_next[m];
                end
            end

            // 5. Parallel-Load and Shift Output Register (Streams [0, 2, 4, 6, 1, 3, 5, 7])
            if (load_sr) begin
                out_data  <= trunc_out[0];
                out_sr[0] <= trunc_out[1];
                out_sr[1] <= trunc_out[2];
                out_sr[2] <= trunc_out[3];
                out_valid <= 1'b1;
                out_cnt   <= 2'd3;
            end else if (out_cnt > 2'd0) begin
                out_data  <= out_sr[0];
                out_sr[0] <= out_sr[1];
                out_sr[1] <= out_sr[2];
                out_sr[2] <= 14'sd0;
                out_valid <= 1'b1;
                out_cnt   <= out_cnt - 2'd1;
            end else begin
                out_valid <= 1'b0;
            end
        end
    end
endmodule