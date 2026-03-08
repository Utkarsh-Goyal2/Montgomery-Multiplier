module tb_montgomery_handshake;

    logic        clk;
    logic [63:0] a;
    logic [63:0] b;
    logic        taken;
    logic        ready_in;
    logic [63:0] result;
    logic        ready_out;
    logic        given;

    // instantiate the DUT
    montgomery_top dut (
        .clk(clk),
        .a(a),
        .b(b),
        .taken(taken),
        .ready_in(ready_in),
        .result(result),
        .ready_out(ready_out),
        .given(given)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test stimulus
    initial begin
        a = 64'd0;
        b = 64'd0;
        taken = 0;
        given = 0;
        
        repeat(4) @(posedge clk);

        // Test case 1
        $display("\n=== Test 1: Single transaction ===");
        wait(ready_in);
        @(posedge clk);
        
        a = 64'h5;
        b = 64'h7;
        taken = 1;
        
        @(posedge clk);
        taken = 0;

        wait(ready_out);
        $display("Result = 0x%h", result);
        
        @(posedge clk);
        given = 1;
        @(posedge clk);
        given = 0;

        repeat(5) @(posedge clk);

        // Test case 2
        $display("\n=== Test 2 ===");
        wait(ready_in);
        @(posedge clk);
        a = 64'hA;
        b = 64'hF;
        taken = 1;

        @(posedge clk);
        taken = 0;

        wait(ready_out);
        $display("Result = 0x%h", result);
        
        @(posedge clk);
        given = 1;
        @(posedge clk);
        given = 0;

        repeat(10) @(posedge clk);
        $display("\n=== Simulation complete ===");
        $finish;
    end

    // Monitor
    initial begin
        $monitor("t=%0t taken=%b ready_in=%b ready_out=%b given=%b a=%h b=%h result=%h",
                  $time, taken, ready_in, ready_out, given, a, b, result);
    end

    // Dump waves
    initial begin
        $dumpfile("montgomery.vcd");
        $dumpvars(0, tb_montgomery_handshake);
    end

endmodule
