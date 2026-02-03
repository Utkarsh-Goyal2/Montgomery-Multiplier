`timescale 1ns/1ps

module tb_montgomery;

    logic clk;
    logic [63:0] a;
    logic [63:0] b;
    logic [63:0] result;

    montgomery_top dut (
        .clk(clk),
        .a(a),
        .b(b),
        .result(result)
    );

    // Clock
    always #5 clk = ~clk;

    initial begin
        // Dump file setup
        $dumpfile("montgomery.vcd");
        $dumpvars(0, tb_montgomery);

        clk = 0;
        a = 64'd0;
        b = 64'd0;

        #20;

        run_test(64'hFFFFFFFFFFFFFFF0,  64'h01);
        run_test(64'd9,  64'd11);
        run_test(64'd123,64'd456);
        run_test(64'd1000,64'd999);
        run_test(64'd1,  64'd1);
        run_test(64'd25, 64'd40);

        #200;
        $finish;
    end

    task run_test(input [63:0] ta, input [63:0] tb);
        begin
            a = ta;
            b = tb;

            #250;

            $display("a = %0d, b = %0d --> result = %0d", ta, tb, result);
        end
    endtask

endmodule