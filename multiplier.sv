module multiplier (
    input logic clk,
    input logic start,
    input logic[63:0] A,
    input logic[63:0] B,
    output logic[127:0] R,
    output logic done
);

    logic [127:0] psum;
    logic [63:0] a;
    logic [63:0] b;
    logic [4:0] idx;
    logic busy = 1'b0; 
    logic [127:0] add_val;
    logic [127:0] add_shift;
    always @(*) begin
        add_val = 128'd0;
        case (b[1:0])
            2'b00: add_val = 128'd0;
            2'b01: add_val = {64'd0, a};
            2'b10: add_val = {63'd0, a, 1'd0};
            2'b11: add_val = {63'd0, a, 1'd0} + {64'd0, a};
        endcase
    end

    always_ff @(posedge clk) begin
        if(start && !busy) begin
            psum <= 128'd0;
            a <= A;
            b <= B;
            idx <= 5'd0;
            add_shift <= 128'd0;
            busy <= 1'b1;
            done <= 1'b0;
        end
        else if(busy) begin
            if(idx == 5'd0)
                add_shift <= add_val;
            else
                add_shift <= add_shift << 2;
            psum <= psum + add_shift;
            b <= b >> 2;
            idx <= idx + 1;
            if(idx == 5'd31) begin
                R <= psum + add_shift;
                busy <= 1'b0;
                done <= 1'b1;
            end
        end
        else begin
            done <= 1'b0;
        end
    end
endmodule
