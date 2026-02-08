`timescale 1ns/1ps

module tb_montgomery_pipelined;

    // -----------------------------
    // DUT interface (taken/given)
    // -----------------------------
    logic        clk;
    logic [63:0] a;
    logic [63:0] b;
    logic        taken;      // from TB -> DUT (we assert when we want to send and DUT is ready)
    logic        ready_in;   // from DUT -> TB (DUT can accept input)
    logic [63:0] result;     // from DUT -> TB
    logic        ready_out;  // from DUT -> TB (output valid)
    logic        given;      // from TB -> DUT (we accept output)

    // -----------------------------
    // Constants / reference
    // -----------------------------
    localparam logic [63:0] N = 64'hFFFFFFFFFFFFFFF1;

    // Queue of expected results (for pipelined / back-to-back)
    logic [63:0] exp_q[$];

    // -----------------------------
    // Instantiate DUT
    // -----------------------------
    montgomery_top dut (
        .clk      (clk),
        .a        (a),
        .b        (b),
        .taken    (taken),
        .ready_in (ready_in),
        .result   (result),
        .ready_out(ready_out),
        .given    (given)
    );

    // -----------------------------
    // Clock
    // -----------------------------
    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    // -----------------------------
    // Helpers
    // -----------------------------
    function automatic logic [63:0] ref_modmul(input logic [63:0] aa, input logic [63:0] bb);
        logic [127:0] prod;
        logic [127:0] modv;
        begin
            prod = aa * bb;
            modv = prod % N;          // SystemVerilog supports % on packed vectors
            ref_modmul = modv[63:0];
        end
    endfunction

    // Drive one transaction using taken/ready_in handshake.
    // Holds a,b stable until accepted.
    task automatic send_tx(input logic [63:0] aa, input logic [63:0] bb);
        logic [63:0] exp;
        begin
            exp = ref_modmul(aa, bb);
            exp_q.push_back(exp);

            // Present inputs
            a <= aa;
            b <= bb;

            // Wait until DUT is ready, then pulse taken for 1 cycle
            @(posedge clk);
            while (!ready_in) @(posedge clk);

            taken <= 1'b1;
            @(posedge clk);
            taken <= 1'b0;

            // After accept, inputs can change next cycle; we leave them as-is or overwrite later
        end
    endtask

    // -----------------------------
    // Output consumption + checking
    // -----------------------------
    // Always ready to take output (no backpressure from TB)
    initial begin
        given = 1'b1;
    end

    // Check whenever DUT says output is ready
    always_ff @(posedge clk) begin
        if (ready_out) begin
            if (exp_q.size() == 0) begin
                $fatal(1, "[%0t] DUT produced an output but TB has no expected value queued!", $time);
            end else begin
                logic [63:0] exp;
                exp = exp_q.pop_front();

                if (result !== exp) begin
                    $display("[%0t] MISMATCH!", $time);
                    $display("  got : 0x%016h", result);
                    $display("  exp : 0x%016h", exp);
                    $fatal(1, "Stopping due to mismatch.");
                end else begin
                    $display("[%0t] PASS  result=0x%016h", $time, result);
                end
            end
        end
    end

    // -----------------------------
    // Waveform
    // -----------------------------
    initial begin
        $dumpfile("montgomery_pipelined.vcd");
        $dumpvars(0, tb_montgomery_pipelined);
    end

    // -----------------------------
    // Stimulus
    // -----------------------------
    initial begin
        // Init
        a = '0;
        b = '0;
        taken = 1'b0;

        // Let unknowns settle a bit
        repeat (5) @(posedge clk);

        $display("Time\tready_in\ttaken\tready_out\tgiven\tA\t\t\tB\t\t\tresult");
        $monitor("%0t\t%b\t\t%b\t%b\t\t%b\t%016h\t%016h\t%016h",
                 $time, ready_in, taken, ready_out, given, a, b, result);

        // ---- Test 1
        $display("\nTest 1: a=5, b=7");
        send_tx(64'h5, 64'h7);

        // ---- Test 2
        $display("\nTest 2: a=A, b=F");
        send_tx(64'hA, 64'hF);

        // ---- Test 3: back-to-back (pipelining)
        $display("\nTest 3: back-to-back transactions");

        send_tx(64'h3, 64'h4);  // added
        send_tx(64'h6, 64'h8);  // added


        // Add a few more random-ish tests
        $display("\nTest 4+: a few more values");
        send_tx(64'h0000_0000_0000_0001, 64'h0000_0000_0000_0001);
        send_tx(64'h0000_0000_0000_0002, 64'h0000_0000_0000_0003);
        send_tx(64'h1234_5678_9ABC_DEF0, 64'h0FED_CBA9_8765_4321);
        send_tx(64'hFFFF_FFFF_FFFF_FFFE, 64'h0000_0000_0000_0002);

        // Wait until all expected results drained
        while (exp_q.size() != 0) @(posedge clk);

        // Extra cycles to be safe
        repeat (10) @(posedge clk);

        $display("\nSimulation complete: all tests passed.");
        $finish;
    end

endmodule
