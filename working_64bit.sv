`timescale 1ns/1ps

module montgomery_reduction (
    input  logic        clk,
    input  logic [127:0] T,
    output logic [63:0]  S,
    output logic [63:0]  m,
    output logic [127:0] t_full,
    output logic [63:0]  t
);
    localparam logic [63:0] N     = 64'hFFFFFFFFFFFFFFF1;
    localparam logic [63:0] N_INV = 64'heeeeeeeeeeeeeeef;

    always_ff @(posedge clk) begin
        m      <= T[63:0] * N_INV;
        t_full <= T + (m * N);
        t      <= t_full[127:64];

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

    always_ff @(posedge clk)
        T <= a * R2;

    montgomery_reduction r0 (
        .clk(clk),
        .T(T),
        .S(a_bar),
        .m(),
        .t_full(),
        .t()
    );
endmodule


module montgomery_mul (
    input  logic        clk,
    input  logic [63:0]  a_bar,
    input  logic [63:0]  b_bar,
    output logic [63:0]  out_bar,
    output logic [63:0]  m,
    output logic [127:0] t_full,
    output logic [63:0]  t
);
    logic [127:0] T;

    always_ff @(posedge clk)
        T <= a_bar * b_bar;

    montgomery_reduction r1 (
        .clk(clk),
        .T(T),
        .S(out_bar),
        .m(m),
        .t_full(t_full),
        .t(t)
    );
endmodule


module montgomery_convert_out (
    input  logic        clk,
    input  logic [63:0]  a_bar,
    output logic [63:0]  a
);
    logic [127:0] T;

    always_ff @(posedge clk)
        T <= {64'd0, a_bar};

    montgomery_reduction r2 (
        .clk(clk),
        .T(T),
        .S(a),
        .m(),
        .t_full(),
        .t()
    );
endmodule


module montgomery_top (
    input  logic        clk,
    input  logic [63:0]  a,
    input  logic [63:0]  b,
    output logic [63:0]  result,
    output logic [63:0]  a_bar,
    output logic [63:0]  b_bar,
    output logic [63:0]  m,
    output logic [127:0] t_full,
    output logic [63:0]  t
);
    logic [63:0] ab_bar;

    montgomery_convert_in  u1 (clk, a, a_bar);
    montgomery_convert_in  u2 (clk, b, b_bar);

    montgomery_mul u3 (
        .clk(clk),
        .a_bar(a_bar),
        .b_bar(b_bar),
        .out_bar(ab_bar),
        .m(m),
        .t_full(t_full),
        .t(t)
    );

    montgomery_convert_out u4 (clk, ab_bar, result);
endmodule