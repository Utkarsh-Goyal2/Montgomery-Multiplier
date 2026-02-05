module tb_montgomery_pipelined;
    logic        clk;
    logic        rst_n;
    logic [63:0] a;
    logic [63:0] b;
    logic        valid_in;
    logic        ready_out;
    logic [63:0] result;
    logic        valid_out;
    logic        ready_in;

    // Instantiate the DUT
    montgomery_top_pipelined dut (
        .clk(clk),
        .rst_n(rst_n),
        .a(a),
        .b(b),
        .valid_in(valid_in),
        .ready_out(ready_out),
        .result(result),
        .valid_out(valid_out),
        .ready_in(ready_in)
    );

    // Clock generation
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test stimulus
    initial begin
        // Initialize
        rst_n = 0;
        a = 64'd0;
        b = 64'd0;
        valid_in = 0;
        ready_in = 1; // Always ready to accept output
        
        // Reset
        repeat(2) @(posedge clk);
        rst_n = 1;
        repeat(2) @(posedge clk);

        // Test case 1: Simple multiplication
        $display("Test 1: Starting at time %0t", $time);
        @(posedge clk);
        a = 64'h5;
        b = 64'h7;
        valid_in = 1;
        
        @(posedge clk);
        if (ready_out) begin
            valid_in = 0; // Deassert after one cycle
        end else begin
            @(posedge clk iff ready_out);
            valid_in = 0;
        end

        // Wait for result
        @(posedge clk iff valid_out);
        $display("Test 1: Result = 0x%h at time %0t", result, $time);
        
        // Wait some cycles
        repeat(5) @(posedge clk);

        // Test case 2: Another multiplication
        $display("Test 2: Starting at time %0t", $time);
        @(posedge clk);
        a = 64'hA;
        b = 64'hF;
        valid_in = 1;
        
        @(posedge clk);
        if (ready_out) begin
            valid_in = 0;
        end else begin
            @(posedge clk iff ready_out);
            valid_in = 0;
        end

        @(posedge clk iff valid_out);
        $display("Test 2: Result = 0x%h at time %0t", result, $time);

        // Test case 3: Back-to-back transactions (pipelining)
        repeat(5) @(posedge clk);
        $display("Test 3: Back-to-back transactions starting at time %0t", $time);
        
        // Send first transaction
        @(posedge clk);
        a = 64'h3;
        b = 64'h4;
        valid_in = 1;
        
        // Wait one cycle, then send second transaction
        @(posedge clk);
        if (ready_out) begin
            a = 64'h6;
            b = 64'h8;
            valid_in = 1;
        end
        
        @(posedge clk);
        valid_in = 0;

        // Collect both results
        @(posedge clk iff valid_out);
        $display("Test 3a: First result = 0x%h at time %0t", result, $time);
        
        @(posedge clk iff valid_out);
        $display("Test 3b: Second result = 0x%h at time %0t", result, $time);

        repeat(10) @(posedge clk);
        $display("Simulation complete");
        $finish;
    end

    // Monitor
    initial begin
        $display("Time\tRst\tValid_in\tReady_out\tValid_out\tReady_in\tA\t\tB\t\tResult");
        $monitor("%0t\t%b\t%b\t\t%b\t\t%b\t\t%b\t\t%h\t%h\t%h", 
                 $time, rst_n, valid_in, ready_out, valid_out, ready_in, a, b, result);
    end

    // Optional: Dump waveforms
    initial begin
        $dumpfile("montgomery_pipelined.vcd");
        $dumpvars(0, tb_montgomery_pipelined);
    end

endmodule