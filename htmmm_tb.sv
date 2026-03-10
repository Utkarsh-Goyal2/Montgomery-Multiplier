`timescale 1ns/1ps

module htmmm_tb;

    // Parameters matching top_HTMMM_NAF defaults
    parameter N = 4;
    parameter d = 3;
    parameter [N+1:0] M_POS     = 6'b010000;
    parameter [N+1:0] M_NEG     = 6'b000001;
    parameter [N+1:0] M_INV_POS = 6'b010001;
    parameter [N+1:0] M_INV_NEG = 6'b000000;

    // DUT signals
    logic           clk;
    logic [N-1:0]   A, B;
    logic [N-1:0]   C;   // NOTE: top declares output [N:0] C inside final_result_opt
                         // but top port is [N-1:0] C — match exactly

    // Instantiate DUT
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

    // Clock: 10 ns period
    initial clk = 0;
    always #5 clk = ~clk;

    // VCD dump
    initial begin
        $dumpfile("htmmm.vcd");
        $dumpvars(0, htmmm_tb);
    end

    // Stimulus
    // Pipeline is 4 stages deep (multiply -> NLTM -> NFHTM -> final_result_opt)
    // so outputs appear 4 cycles after input
    integer i, j;
    initial begin
        A = 0; B = 0;
        @(posedge clk); #1;

        // Sweep a few input combinations
        for (i = 3; i < 2**N; i = i + 1) begin
            for (j =1; j < 2**N; j = j + 1) begin
                A = i[N-1:0];
                B = j[N-1:0];
                repeat (10) @(posedge clk) #1;
            end
        end

        // Flush pipeline (4 extra cycles)
       //S repeat (4) @(posedge clk);

        $display("Simulation done. C final = %0d", C);
        $finish;
    end

    // Monitor output
    initial begin
        $monitor("t=%0t | A=%0d B=%0d | C=%0d", $time, A, B, C);
    end

endmodule