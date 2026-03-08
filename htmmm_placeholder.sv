// Stage 1: Calculate m = T[63:0] * N_INV
module reduction_stage1 (
    input  logic clk,

    //T in montgomery
    input  logic [127:0] T,

    //if taken = 1 at the rising edge of the clock this stage captures the input and processes it
    input  logic taken,

    //ready_in tells the previous block whether this stage is ready to accept a new input ie
    //ready_in = 1 means it can take data and ready_in = 0 means it is busy
    output logic ready_in,

    //stored copy of T that will be passed to the next stage.
    output logic [127:0] T_out,

    //Q or m in montgomery
    output logic [63:0] m,

    //ready_out tells the next stage whether this stage has valid output ready ie
    //if ready_out = 1 means output is valid and if ready_out = 0 means no valid data yet
    output logic ready_out,

    //if given = 1 the next stage has already taken this stage's output
    //so it can clear it's valid flag.
    input  logic given,


    //to check if TL=0 ie tl_zero = 1 means T[63:0] == 0
    output logic tl_zero 
);
    //M' in Montgomery
    localparam logic [63:0] N_INV = 64'heeeeeeeeeeeeeeef;

    //T_reg is mainly used to make it clear that this is an internal pipeline register
    //and T_out is just the output view of that register
    logic [127:0] T_reg = 128'd0;

    //again same thing as T_reg and T_out 
    logic [63:0]  m_reg = 64'd0;


    //register to check if TL=0 (same logic as T_reg and T_out)  
    logic tl_zerocheck_reg = 1'b0; 

    //valid = 0 means stage is empty
    //valid = 1 means stage contains ready output
    //because this stage finishes its work in the same clock edge where it accepts input.
    logic valid = 1'b0; 
    
    always_ff @(posedge clk) begin

        //helper register 
        logic [127:0] m_tmp;

        //If taken = 1 this stage is accepting a new input now
        if (taken) begin
        
            //after the clock edge, T_reg will hold the current T
            T_reg <= T; 

            //compute full 128-bit product of T_low and N_INV
            m_tmp = ({64'd0, T[63:0]} * {64'd0, N_INV}); 

            //m = (T_low * N_INV) mod 2^64, so keep only lower 64 bits
            m_reg <= m_tmp[63:0];

            //remember whether lower 64 bits of T ie TL are zero
            tl_zerocheck_reg <= (T[63:0] == 64'd0);   

            //output ready                     
            valid <= 1'b1;
        end 

        else if (given) begin

            //clear valid after next stage accepts this output
            valid <= 1'b0;
        end
    end
    
    //passing useful data forward
    assign T_out = T_reg;
    assign m = m_reg;
    assign tl_zero = tl_zerocheck_reg; 

    //setting control signals
    assign ready_in = !valid || given;
    assign ready_out = valid;

endmodule




// Stage 2: Compute upper-part HTMMM sum using T_H, high(m*N), and carry correction
module reduction_stage2 (
    input  logic clk,

    //128-bit T passed from stage 1
    input  logic [127:0] T,

    //m = (TL​*N_INV) mod 2^64
    input  logic [63:0] m,

    //signal from stage 1 telling stage 2 whether TL=T[63:0]=0
    input logic tl_zero, 

    //same as above
    input  logic taken,
    output logic ready_in,
    output logic ready_out,
    input  logic given,

    //t_htmmm = TH ​+ SH + carry
    output logic [64:0] t_htmmm, 

    //passes the tl_zero information forward to the next stage
    output logic tl_zero_out 
    
);
    localparam logic [63:0] N = 64'hFFFFFFFFFFFFFFF1;

    //internal register that stores the computed stage 2 result 
    //(possible extra carry makes result 65 bits)
    logic [64:0] t_htmmm_reg = 65'd0; 

    //stores the incoming tl_zero so it can be passed onward as a registered signal.
    logic tl_zerocheck_reg = 1'b0; 

    //same as before ie valid = 1 means t_htmmm_reg contains valid output for the next stage
    logic valid = 1'b0;  
    
    always_ff @(posedge clk) begin
        if (taken) begin

            //stores the full 128-bit product of m * N
            logic [127:0] prod;

            //temporary variable for the high 64 bits of the product m * N
            logic [63:0] s_h; 

            //temporary variable for the sum
            //c = TH + SH + carry
            logic [64:0] c; 


            prod = ({64'd0, m} * {64'd0, N});           
            s_h = prod[127:64];
            c = {1'b0, T[127:64]} + {1'b0, s_h}; 

            //// if lower half of T is non-zero add carry correction of 1 to upper-part sum
            if (!tl_zero) begin 
                c = c + 65'd1;
            end

            //t_htmmm_reg holds the result for the next stage.
            t_htmmm_reg <= c; 

            //forward tl_zero to next stage as a registered signal
            tl_zerocheck_reg <= tl_zero;

            //valid same as above 
            valid <= 1'b1;
        end
 
        else if (given) begin
            valid <= 1'b0;
        end
    end
    
    //same assignment technique as above
    assign t_htmmm = t_htmmm_reg; 
    assign tl_zero_out = tl_zerocheck_reg; 
    assign ready_in = !valid || given;
    assign ready_out = valid;
endmodule




// Stage 3: Calculate t[127:64] and final comparison
module reduction_stage3 (
    input  logic clk,
    input  logic [64:0] t_htmmm, 
    input tl_zero, 
    input  logic taken,
    output logic ready_in,
    output logic [63:0] S,
    output logic ready_out,
    input  logic given
);
    localparam logic [63:0] N = 64'hFFFFFFFFFFFFFFF1;
    logic [63:0] S_reg = 64'd0; 
    logic valid         = 1'b0; 
    
    always_ff @(posedge clk) begin
        if (taken) begin
            logic [64:0] t;       
            logic [64:0] t_minus; 
            t = t_htmmm;  
            if (t >= {1'b0, N}) begin
                t_minus = t - {1'b0, N}; 
                S_reg <= t_minus[63:0];  
            end else begin
                S_reg <= t[63:0];        
            end
            valid <= 1'b1;
        end 
        else if (given) begin
            valid <= 1'b0;
        end
    end
    
    assign S = S_reg;
    assign ready_in = !valid || given;
    assign ready_out = valid;
endmodule


// reduction module connecting all 3 stages
module reduction (
    input  logic clk,
    input  logic [127:0] T,
    input  logic taken,
    output logic ready_in,
    output logic [63:0] S,
    output logic ready_out,
    input  logic given
);
    logic [127:0] T_stage1_out;
    logic [63:0]  m_stage1;
    logic tl_zero_stage1; 
    logic ready_out_stage1, ready_in_stage2;
    logic taken_stage2, given_stage1;
    
    logic [64:0] t_htmmm_stage2; 
    logic tl_zero_stage2;  
    logic ready_out_stage2, ready_in_stage3;
    logic taken_stage3, given_stage2;
    
    reduction_stage1 u_stage1 (
        .clk(clk),
        .T(T),
        .taken(taken),
        .ready_in(ready_in),
        .T_out(T_stage1_out),
        .m(m_stage1),
        .ready_out(ready_out_stage1),
        .given(given_stage1),
        .tl_zero(tl_zero_stage1) 
    );
    
    assign taken_stage2 = ready_out_stage1 && ready_in_stage2;
    assign given_stage1 = taken_stage2;
    
    reduction_stage2 u_stage2 (
        .clk(clk),
        .T(T_stage1_out),
        .m(m_stage1),
        .tl_zero(tl_zero_stage1), 
        .taken(taken_stage2),
        .ready_in(ready_in_stage2),
        .t_htmmm(t_htmmm_stage2), 
        .tl_zero_out(tl_zero_stage2), 
        .ready_out(ready_out_stage2),
        .given(given_stage2)
    );
    
    assign taken_stage3 = ready_out_stage2 && ready_in_stage3;
    assign given_stage2 = taken_stage3;
    
    reduction_stage3 u_stage3 (
        .clk(clk),
        .t_htmmm(t_htmmm_stage2), 
        .tl_zero(tl_zero_stage2), 
        .taken(taken_stage3),
        .ready_in(ready_in_stage3),
        .S(S),
        .ready_out(ready_out),
        .given(given)
    );
endmodule


module montgomery_convert_in (
    input  logic clk,
    input  logic [63:0] a,
    input  logic taken,
    output logic ready_in,
    output logic [63:0] a_bar,
    output logic ready_out,
    input  logic given
);
    localparam logic [63:0] R2 = 64'he1;
    logic [127:0] T = 128'd0;   
    logic valid_mult = 1'b0;     
    logic ready_redc_in;
    logic given_to_redc;

    always_ff @(posedge clk) begin
        if (taken) begin
            T <= ({64'd0, a} * {64'd0, R2}); 
            valid_mult <= 1'b1;
        end 
        else if (given_to_redc) begin
            valid_mult <= 1'b0;
        end
    end

    assign ready_in = !valid_mult || ready_redc_in;
    assign given_to_redc = valid_mult && ready_redc_in;

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
    input  logic clk,
    input  logic [63:0] a_bar,
    input  logic [63:0] b_bar,
    input  logic taken,
    output logic ready_in,
    output logic [63:0] out_bar,
    output logic ready_out,
    input  logic given
);
    logic [127:0] T = 128'd0; 
    logic valid_mult = 1'b0;  
    logic ready_redc_in;
    logic given_to_redc;

    always_ff @(posedge clk) begin
        if (taken) begin
            T <= ({64'd0, a_bar} * {64'd0, b_bar}); 
            valid_mult <= 1'b1;
        end 
        else if (given_to_redc) begin
            valid_mult <= 1'b0;
        end
    end

    assign ready_in = !valid_mult || ready_redc_in;
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
    input  logic clk,
    input  logic [63:0] a_bar,
    input  logic taken,
    output logic ready_in,
    output logic [63:0] a,
    output logic ready_out,
    input  logic given
);
    logic [127:0] T = 128'd0; 
    logic valid_prep = 1'b0;  
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

    assign ready_in = !valid_prep || ready_redc_in;
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
    input  logic clk,
    input  logic [63:0] a,
    input  logic [63:0] b,
    input  logic taken,
    output logic ready_in,
    output logic [63:0] result,
    output logic ready_out,
    input  logic given
);
    logic [63:0] a_bar, b_bar, ab_bar;
    logic ready_in_a, ready_in_b, ready_in_mul, ready_in_out;
    logic ready_out_a, ready_out_b, ready_out_mul;
    logic taken_a, taken_b, taken_mul, taken_out;
    logic given_a, given_b, given_mul;
    
    logic [63:0] a_reg = 64'd0, b_reg = 64'd0;
    logic inputs_valid = 1'b0;

    always_ff @(posedge clk) begin
        if (taken) begin
            a_reg <= a;
            b_reg <= b;
            inputs_valid <= 1'b1;
        end else if (taken_a && taken_b) begin
            inputs_valid <= 1'b0;
        end
    end

    assign ready_in = !inputs_valid || (ready_in_a && ready_in_b);
    assign taken_a = inputs_valid && ready_in_a && ready_in_b;
    assign taken_b = taken_a;

    montgomery_convert_in u_in_a (
        .clk(clk), .a(a_reg), .taken(taken_a),
        .ready_in(ready_in_a), .a_bar(a_bar),
        .ready_out(ready_out_a), .given(given_a)
    );

    montgomery_convert_in u_in_b (
        .clk(clk), .a(b_reg), .taken(taken_b),
        .ready_in(ready_in_b), .a_bar(b_bar),
        .ready_out(ready_out_b), .given(given_b)
    );

    assign taken_mul = ready_out_a && ready_out_b && ready_in_mul;
    assign given_a = taken_mul;
    assign given_b = taken_mul;

    montgomery_mul u_mul (
        .clk(clk), .a_bar(a_bar), .b_bar(b_bar),
        .taken(taken_mul), .ready_in(ready_in_mul),
        .out_bar(ab_bar), .ready_out(ready_out_mul),
        .given(given_mul)
    );

    assign taken_out = ready_out_mul && ready_in_out;
    assign given_mul = taken_out;

    montgomery_convert_out u_out (
        .clk(clk), .a_bar(ab_bar), .taken(taken_out),
        .ready_in(ready_in_out), .a(result),
        .ready_out(ready_out), .given(given)
    );
endmodule
