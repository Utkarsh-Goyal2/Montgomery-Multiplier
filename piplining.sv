// cxalculate m
module reduction_stage1 (
    input  logic clk,
    input  logic [127:0] T,
    input  logic taken,
    output logic ready_in,
    output logic [127:0] T_out,
    output logic [63:0] m,
    output logic ready_out,
    input  logic given
);
    localparam logic [63:0] N_INV = 64'heeeeeeeeeeeeeeef;
    
    logic [127:0] T_reg;
    logic [63:0] m_reg;
    logic valid;
    
    always_ff @(posedge clk) begin
        if (taken) begin
            T_reg <= T;
            m_reg <= T[63:0] * N_INV;
            valid <= 1'b1;
        end else if (given) begin
            valid <= 1'b0;
        end
    end
    
    assign T_out = T_reg;
    assign m = m_reg;
    assign ready_in = !valid || given;
    assign ready_out = valid;
endmodule

// calculate t_full = T + (m * N)
module reduction_stage2 (
    input  logic clk,
    input  logic [127:0] T,
    input  logic [63:0] m,
    input  logic taken,
    output logic ready_in,
    output logic [127:0] t_full,
    output logic ready_out,
    input  logic given
);
    localparam logic [63:0] N = 64'hFFFFFFFFFFFFFFF1;
    
    logic [127:0] t_full_reg;
    logic valid;
    
    always_ff @(posedge clk) begin
        if (taken) begin
            t_full_reg <= T + (m * N);
            valid <= 1'b1;
        end else if (given) begin
            valid <= 1'b0;
        end
    end
    
    assign t_full = t_full_reg;
    assign ready_in = !valid || given;
    assign ready_out = valid;
endmodule

//calculate t[127:64] and final comparison
module reduction_stage3 (
    input  logic clk,
    input  logic [127:0] t_full,
    input  logic taken,
    output logic ready_in,
    output logic [63:0] S,
    output logic ready_out,
    input  logic given
);
    localparam logic [63:0] N = 64'hFFFFFFFFFFFFFFF1;
    
    logic [63:0] S_reg;
    logic valid;
    
    always_ff @(posedge clk) begin
        if (taken) begin
            if (t_full[127:64] >= N)
                S_reg <= t_full[127:64] - N;
            else
                S_reg <= t_full[127:64];
            valid <= 1'b1;
        end else if (given) begin
            valid <= 1'b0;
        end
    end
    
    assign S = S_reg;
    assign ready_in = !valid || given;
    assign ready_out = valid;
endmodule

//  reduction module connecting all 3 stages
module reduction (
    input  logic clk,
    input  logic [127:0] T,
    input  logic taken,
    output logic ready_in,
    output logic [63:0] S,
    output logic ready_out,
    input  logic given
);
    // connection signals
    logic [127:0] T_stage1_out;
    logic [63:0] m_stage1;
    logic ready_out_stage1, ready_in_stage2;
    logic taken_stage2, given_stage1;
    
    logic [127:0] t_full_stage2;
    logic ready_out_stage2, ready_in_stage3;
    logic taken_stage3, given_stage2;
    
    // Stage 1
    reduction_stage1 u_stage1 (
        .clk(clk),
        .T(T),
        .taken(taken),
        .ready_in(ready_in),
        .T_out(T_stage1_out),
        .m(m_stage1),
        .ready_out(ready_out_stage1),
        .given(given_stage1)
    );
    
    // Connection: Stage 1 -> Stage 2
    assign taken_stage2 = ready_out_stage1 && ready_in_stage2;
    assign given_stage1 = taken_stage2;
    
    // Stage 2
    reduction_stage2 u_stage2 (
        .clk(clk),
        .T(T_stage1_out),
        .m(m_stage1),
        .taken(taken_stage2),
        .ready_in(ready_in_stage2),
        .t_full(t_full_stage2),
        .ready_out(ready_out_stage2),
        .given(given_stage2)
    );
    
    // Connection: Stage 2 -> Stage 3
    assign taken_stage3 = ready_out_stage2 && ready_in_stage3;
    assign given_stage2 = taken_stage3;
    
    // Stage 3
    reduction_stage3 u_stage3 (
        .clk(clk),
        .t_full(t_full_stage2),
        .taken(taken_stage3),
        .ready_in(ready_in_stage3),
        .S(S),
        .ready_out(ready_out),
        .given(given)
    );
    
endmodule

module montgomery_convert_in (
    input  logic        clk,
    input  logic [63:0] a,
    input  logic        taken,        
    output logic        ready_in,     
    output logic [63:0] a_bar,
    output logic        ready_out,    
    input  logic        given         
);
    localparam logic [63:0] R2 = 64'he1;

    logic [127:0] T;
    logic valid_mult;
    logic ready_redc_in;
    logic given_to_redc;

    // Multiply a * R2
    always_ff @(posedge clk) begin
        if (taken) begin
            T <= a * R2;
            valid_mult <= 1'b1;
        end else if (given_to_redc) begin
            valid_mult <= 1'b0;
        end
    end

    // ready to accept input when multiplication stage is free
    assign ready_in = !valid_mult || (valid_mult && ready_redc_in);
    
    assign given_to_redc = valid_mult && ready_redc_in;

    // Reduction module
    reduction u_redc (
        .clk(clk),
        .T(T),
        .taken(given_to_redc),
        .ready_in(ready_redc_in),
        .S(a_bar),
        .ready_out(ready_out),
        .given(given)
    );
endmodule

module montgomery_mul (
    input  logic        clk,
    input  logic [63:0] a_bar,
    input  logic [63:0] b_bar,
    input  logic        taken,        
    output logic        ready_in,     
    output logic [63:0] out_bar,
    output logic        ready_out,    
    input  logic        given         
);
    logic [127:0] T;
    logic valid_mult;
    logic ready_redc_in;
    logic given_to_redc;

    // multiply a_bar * b_bar
    always_ff @(posedge clk) begin
        if (taken) begin
            T <= a_bar * b_bar;
            valid_mult <= 1'b1;
        end else if (given_to_redc) begin
            valid_mult <= 1'b0;
        end
    end

    assign ready_in = !valid_mult || (valid_mult && ready_redc_in);
    assign given_to_redc = valid_mult && ready_redc_in;

    reduction u_redc (
        .clk(clk),
        .T(T),
        .taken(given_to_redc),
        .ready_in(ready_redc_in),
        .S(out_bar),
        .ready_out(ready_out),
        .given(given)
    );
endmodule

module montgomery_convert_out (
    input  logic        clk,
    input  logic [63:0] a_bar,
    input  logic        taken,        
    output logic        ready_in,     
    output logic [63:0] a,
    output logic        ready_out,    
    input  logic        given         
);
    logic [127:0] T;
    logic valid_prep;
    logic ready_redc_in;
    logic given_to_redc;


    always_ff @(posedge clk) begin
        if (taken) begin
            T <= {64'd0, a_bar};
            valid_prep <= 1'b1;
        end else if (given_to_redc) begin
            valid_prep <= 1'b0;
        end
    end

    assign ready_in = !valid_prep || (valid_prep && ready_redc_in);
    assign given_to_redc = valid_prep && ready_redc_in;

    reduction u_redc (
        .clk(clk),
        .T(T),
        .taken(given_to_redc),
        .ready_in(ready_redc_in),
        .S(a),
        .ready_out(ready_out),
        .given(given)
    );
endmodule

module montgomery_top (
    input  logic        clk,
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic        taken,        
    output logic        ready_in,     
    output logic [63:0] result,
    output logic        ready_out,    
    input  logic        given         
);
    // Signals between modules
    logic [63:0] a_bar, b_bar;
    logic [63:0] ab_bar;
    
    logic ready_in_a, ready_in_b, ready_in_mul, ready_in_out;
    logic ready_out_a, ready_out_b, ready_out_mul, ready_out_out;
    logic taken_a, taken_b, taken_mul, taken_out;
    logic given_a, given_b, given_mul, given_out;
    
    logic [63:0] a_reg, b_reg;
    logic inputs_valid;
    
    always_ff @(posedge clk) begin
        if (taken) begin
            a_reg <= a;
            b_reg <= b;
            inputs_valid <= 1'b1;
        end else if (taken_a && taken_b) begin
            // inputs have been taken by convert modules
            inputs_valid <= 1'b0;
        end
    end
    
    
    assign ready_in = !inputs_valid || (ready_in_a && ready_in_b);
    
    // Convert modules take input when we have valid inputs and they're ready
    assign taken_a = inputs_valid && ready_in_a && ready_in_b;
    assign taken_b = inputs_valid && ready_in_a && ready_in_b;

    montgomery_convert_in u_in_a (
        .clk(clk),
        .a(a_reg),
        .taken(taken_a),
        .ready_in(ready_in_a),
        .a_bar(a_bar),
        .ready_out(ready_out_a),
        .given(given_a)
    );

    montgomery_convert_in u_in_b (
        .clk(clk),
        .a(b_reg),
        .taken(taken_b),
        .ready_in(ready_in_b),
        .a_bar(b_bar),
        .ready_out(ready_out_b),
        .given(given_b)
    );

    // after both conversions pass to multiplier
    logic both_ready;
    assign both_ready = ready_out_a && ready_out_b;
    assign taken_mul = both_ready && ready_in_mul;
    assign given_a = taken_mul;
    assign given_b = taken_mul;

    montgomery_mul u_mul (
        .clk(clk),
        .a_bar(a_bar),
        .b_bar(b_bar),
        .taken(taken_mul),
        .ready_in(ready_in_mul),
        .out_bar(ab_bar),
        .ready_out(ready_out_mul),
        .given(given_mul)
    );

    assign taken_out = ready_out_mul && ready_in_out;
    assign given_mul = taken_out;

    montgomery_convert_out u_out (
        .clk(clk),
        .a_bar(ab_bar),
        .taken(taken_out),
        .ready_in(ready_in_out),
        .a(result),
        .ready_out(ready_out),
        .given(given)
    );
endmodule