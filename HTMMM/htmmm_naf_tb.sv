`timescale 1ns/1ps

// Correct testbench for top_HTMMM_NAF
// Pipeline latency: 10 clock cycles from input applied to output valid
// Verification: exhaustive sweep A,B in [0,M) vs golden (A*B) % M

module htmmm_tb_fixed;
    parameter N       = 4;
    parameter d       = 3;
    parameter M       = 15;
    parameter LATENCY = 9;   // shift-register depth to align A/B with output
                              // (input captured at posedge+1, output valid 10 cycles later
                              //  => pipe depth for comparison = 9)

    parameter [N+1:0] M_POS     = 6'b010000;
    parameter [N+1:0] M_NEG     = 6'b000001;
    parameter [N+1:0] M_INV_POS = 6'b010001;
    parameter [N+1:0] M_INV_NEG = 6'b000000;

    logic         clk;
    logic [N-1:0] A, B, C;

    top_HTMMM_NAF #(
        .N         (N),
        .d         (d),
        .M_POS     (M_POS),
        .M_NEG     (M_NEG),
        .M_INV_POS (M_INV_POS),
        .M_INV_NEG (M_INV_NEG)
    ) dut (
        .clk (clk),
        .A   (A),
        .B   (B),
        .C   (C)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        $dumpfile("htmmm.vcd");
        $dumpvars(0, htmmm_tb_fixed);
    end

    // Shift registers to delay A/B by LATENCY cycles for comparison
    reg [N-1:0] A_pipe [0:LATENCY];
    reg [N-1:0] B_pipe [0:LATENCY];
    integer k;
    always_ff @(posedge clk) begin
        A_pipe[0] <= A; B_pipe[0] <= B;
        for (k = 1; k <= LATENCY; k++) begin
            A_pipe[k] <= A_pipe[k-1];
            B_pipe[k] <= B_pipe[k-1];
        end
    end

    integer i, j, cyc, errors, tests;
    integer exp_val;

    initial begin
        errors = 0; tests = 0; cyc = 0;
        A = 0; B = 0;
        for (k = 0; k <= LATENCY; k++) begin A_pipe[k] = 0; B_pipe[k] = 0; end
        @(posedge clk); #1;

        // Exhaustive sweep
        for (i = 0; i < M; i++) begin
            for (j = 0; j < M; j++) begin
                A = i[N-1:0];
                B = j[N-1:0];
                @(posedge clk); #1;
                cyc++;
                if (cyc > LATENCY) begin
                    exp_val = (A_pipe[LATENCY] * B_pipe[LATENCY]) % M;
                    if (C !== exp_val[N-1:0]) begin
                        $display("FAIL: A=%0d B=%0d => C=%0d, expected=%0d",
                                  A_pipe[LATENCY], B_pipe[LATENCY], C, exp_val);
                        errors++;
                    end
                    tests++;
                end
            end
        end

        // Flush remaining pipeline
        for (i = 0; i <= LATENCY + 1; i++) begin
            A = 0; B = 0;
            @(posedge clk); #1;
            exp_val = (A_pipe[LATENCY] * B_pipe[LATENCY]) % M;
            if (C !== exp_val[N-1:0]) begin
                $display("FAIL(flush): A=%0d B=%0d => C=%0d, expected=%0d",
                          A_pipe[LATENCY], B_pipe[LATENCY], C, exp_val);
                errors++;
            end
            tests++;
        end

        $display("=== Simulation complete: %0d errors / %0d tests ===", errors, tests);
        if (errors == 0) $display("ALL PASS");
        $finish;
    end

endmodule