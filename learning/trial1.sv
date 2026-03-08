unsigned int radix_size = 64;
logic R[radix_size:0] = {1,radix_size{0}}; // radix being used
unsigned int N = 0xFFFFFFFFFFFFFFF1; //odd modulus
logic N_INV = 0x01;
logic R_SQR = 0x01;
module reduction(input logic T, input logic m,input logic clk, output logic S)
    logic t;
    t <= (T + m*N ) >> radix_size;
    always @(posedge clk) begin
        if(t > N) S = t - N;
        else S = t;
    end
endmodule

module montgomery_domain_conversion(input logic a, input logic clk, output logic a_bar)
    logic t,m;
    assign t = (a * R_SQR);
    assign m = ((t[radix_size-1:0])*N');
    reduction get_abar(t.(T), m.(m), clk.(clk), a_bar.(S));
endmodule

module controller(input logic a, input logic b, input logic clk)
    logic a_bar, b_bar, out;
    montgomery_domain_conversion precalc_a(a.(a), clk.(clk), a_bar.(a_bar))
    montgomery_domain_conversion precalc_b(b.(a), clk.(clk), b_bar.(a_bar))
    assign T = a_bar * b_bar;
    assign m = ((T[radix_size-1:0]) * N') ;
    reduction find_mod(T.(T), m.(m), clk.(clk), out.(S));
endmodule
