module montgomery_mul (
    input  wire         clk,
    input  wire         rst_n,
    input  wire [15:0]  a,
    input  wire [15:0]  b,
    input  wire         start, // input_valid for THIS cycle
    //means while giving the input do we want an output or not depends on what we give here
    //start= 1 recognises it as valid input and then it gives valid output and start=0.....
    output reg  [15:0]  result,
    output reg          Valid
);

    // Constants: M = 65521, R = 2^16
    // M' = -M^{-1} mod R = 61167
    localparam [15:0] M       = 16'd65521;
    localparam [15:0] M_PRIME = 16'd61167;
    

    reg [3:0] vpipe; //4 stage pipeline
    //we now have a register at the end of every phase (VVVVIP)
    reg [15:0] a0, b0; //stage 0 to capture the inputs
    reg [31:0] T1; //stage 1 register for T = a*b
    //stage 2 register (m, mM)
    reg [15:0] m2;
    reg [31:0] mM2;
    reg [31:0] T2; //also this to carry the T forward for add stage
    //stage 3 registers (S, t)
    reg [32:0] S3;
    reg [15:0] t3;
    //stage 4 reg (result)
    reg [15:0] res4;

    
    //combinational between stages
    wire [31:0] T1_next = a0 * b0; //we'll then feed this T1_next to T1
    //stage 2 
    wire [31:0] m_full2 = T1[15:0] * M_PRIME;
    wire [15:0] m2_next = m_full2[15:0]; //mod R 
    wire [31:0] mM2_next = m2_next * M; //then feed m2_next to m2 and mm2_next to mm2
    //we also feed T1 to T2 again as we need it in the next stage
    //stage 3
    wire [32:0] S3_next = {1'b0, T2} + {1'b0, mM2};
    wire [15:0] t3_next = S3_next[31:16]; // divide by R = 2^16
    //stage 4
    wire [15:0] res4_next = (t3_next >= M) ? (t3_next - M) : t3_next; //final result


    // Sequential pipeline registers
    always @(posedge clk or negedge rst_n) begin //positive clock edge and active low reset button
        if (!rst_n) begin
            //just setting everything to 0
            vpipe  <= 4'b0000;
            valid  <= 1'b0;
            result <= 16'd0;
            a0   <= 16'd0;
            b0   <= 16'd0;
            T1   <= 32'd0;
            m2   <= 16'd0;
            mM2  <= 32'd0;
            T2   <= 32'd0;
            S3   <= 33'd0;
            t3   <= 16'd0;
            res4 <= 16'd0;
        end 

        else begin
            // valid shifts with start as "input_valid"
            vpipe <= {vpipe[2:0], start}; //this is concatenation here so what it does is it 
            //shifts the “this input is valid” information through the pipeline one stage per clock 
            //so the output knows exactly when the result is real
            //like for example
            //vpipe <= {010, 0} → 0100
            //vpipe <= {100, 0} → 1000   ← output valid
            //as valid  <= vpipe[3]; (code down)

            //stage 0 capture (even if start=0, it becomes a bubble)
            a0 <= a;
            b0 <= b;
            //even if start=0, a0 b0 still capture something
            //the math still happens
            //But the result is ignored as valid will be 0 when it reaches the output

            //stage 1
            T1 <= T1_next;
            //stage 2
            m2  <= m2_next;
            mM2 <= mM2_next;
            T2  <= T1; //copying T with mM2 for the add stage
            //stage 3
            S3 <= S3_next;
            t3 <= t3_next;
            //stage 4
            res4 <= res4_next;
            //outputs
            valid  <= vpipe[3];
            result <= res4;
        end
    end

endmodule