module reduction (
    input  logic clk,
    input  logic [127:0] T,
    output logic [63:0]  S
);
    localparam logic [63:0] N     = 64'hFFFFFFFFFFFFFFF1;
    localparam logic [63:0] N_INV = 64'heeeeeeeeeeeeeeef; // modular inverse
    logic [63:0]  m;
    logic [127:0] t_full;
    logic [63:0]  t;

    always_ff @(posedge clk) begin
    m <= T[63:0] * N_INV;
    end

    always_ff @(posedge clk) begin
        t_full <= T + (m * N);
    end

    always_ff @(posedge clk) begin
        t <= t_full[127:64];
        if (t >= N)
            S <= t - N;
        else
            S <= t;
    end
endmodule

module montgomery_convert_in (
    input  logic        clk,
    input  logic [63:0]  a,
    output logic [63:0]  a_bar
);
    localparam logic [63:0] R2 = 64'he1;

    logic [127:0] T;

    always_ff @(posedge clk) begin
        T <= a * R2;
    end

    reduction u_redc (
        .clk(clk),
        .T(T),
        .S(a_bar)
    );
endmodule

module montgomery_mul (
    input  logic        clk,
    input  logic [63:0]  a_bar,
    input  logic [63:0]  b_bar,
    output logic [63:0]  out_bar
);
    logic [127:0] T;

    always_ff @(posedge clk) begin
        T <= a_bar * b_bar;
    end

    reduction u_redc (
        .clk(clk),
        .T(T),
        .S(out_bar)
    );
endmodule

module montgomery_convert_out (
    input  logic        clk,
    input  logic [63:0]  a_bar,
    output logic [63:0]  a
);
    logic [127:0] T;

    always_ff @(posedge clk) begin
        T <= {64'd0, a_bar};
    end

    reduction u_redc (
        .clk(clk),
        .T(T),
        .S(a)
    );
endmodule

module montgomery_top (
    input  logic        clk,
    input  logic [63:0]  a,
    input  logic [63:0]  b,
    output logic [63:0]  result
);
    logic [63:0] a_bar, b_bar;
    logic [63:0] ab_bar;

    montgomery_convert_in  u_in_a (.clk(clk), .a(a), .a_bar(a_bar));
    montgomery_convert_in  u_in_b (.clk(clk), .a(b), .a_bar(b_bar));
    montgomery_mul         u_mul  (.clk(clk), .a_bar(a_bar), .b_bar(b_bar), .out_bar(ab_bar));
    montgomery_convert_out u_out  (.clk(clk), .a_bar(ab_bar), .a(result));
endmodule