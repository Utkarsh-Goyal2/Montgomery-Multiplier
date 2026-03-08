module multiply #(
    parameter N = 4
)(
    input  logic             clk,
    input  logic [N+1:0]     a,
    input  logic [N+1:0]     b,
    output logic [2*N+1:0]   T,
    output logic [N+1:0]     T_L,
    output logic [N-1:0]     T_H
);
    logic [2*N+1:0] product;

    always_comb begin
        product = a * b;
    end

    always_ff @(posedge clk) begin
        T   <= product;
        T_L <= product[N+1:0];
        T_H <= product[2*N+1 : N+2];
    end
endmodule



module finding_q #(
    parameter N     = 4,
    parameter [N+1:0] M_INV = 6'b010001   // -M^{-1} mod R
)(
    input  logic         clk,
    input  logic [N+1:0] T_L,
    output logic [N+1:0] Q_L,
    output logic [N+1:0] D
);
    logic [2*N+1:0] q_full;

    always_comb begin
        q_full = T_L * M_INV;
    end

    always_ff @(posedge clk) begin
        Q_L <= q_full[N+1:0];        // mod R: keep lower N+2 bits
        D   <= (~T_L) + 1'b1;        // R - T_L in N+2-bit arithmetic
    end
endmodule



module high_truncation #(
    parameter N          = 4,
    parameter d          = 3,
    parameter [N+1:0] M  = 6'b001111  
)(
    input  logic         clk,
    input  logic [N+1:0] Q_L,
    input  logic [N+1:0] D,
    output logic [N-1:0] S_H
);
    
    logic [2*N+3:0] msp_acc;

    
    logic [d+4:0]   cep_acc; // needs to hold up to (N+2) ones, so d+4 bits to be safe 9change based on N value)

    logic [d-1:0]   d_cal;
    logic [d-1:0]   d_real;
    logic [N-1:0]   U;

    always_comb begin
        msp_acc = '0;
        cep_acc = '0;

        for (int i = 0; i <= N+1; i++) begin
            for (int j = 0; j <= N+1; j++) begin
                if ((i + j) >= (N + 2)) begin
                    // MSP
                    msp_acc[i+j-(N+2)] += (Q_L[i] & M[j]);
                end
                else if ((i + j) >= (N + 2 - d)) begin
                    // CEP
                    cep_acc[(i+j)-(N+2-d)] += (Q_L[i] & M[j]);
                end
                // else LSP
            end
        end

        // d_cal  = top d bits of cep_acc
        // Each position can accumulate up to N+2 ones, so the carry ripple means the "top d bits" that could carry into MSP live at cep_acc[2d-1 : d].
        d_cal  = cep_acc[2*d-1 : d];

        // d_real = D[N+1 : N+2-d]  (top d bits of D)
        d_real = D[N+1 -: d];       

        // MSP output
        U = msp_acc[N-1:0];
    end

    always_ff @(posedge clk) begin
        if (d_cal > d_real)
            S_H <= U + 1'b1;     // lost carry = add correction
        else
            S_H <= U;            // no lost carry
    end

endmodule


module final_result #(
    parameter N = 4
)(
    input  logic         clk,
    input  logic [N-1:0] T_H,
    input  logic [N-1:0] S_H,
    input  logic [N+1:0] T_L,
    output logic [N:0]   C
);
    always_ff @(posedge clk) begin
        if (T_L == '0)
            C <= {1'b0, T_H} + {1'b0, S_H};
        else
            C <= {1'b0, T_H} + {1'b0, S_H} + 1'b1;
    end
endmodule


module top_HTMMM #(
    parameter N               = 4,
    parameter d               = 3,
    parameter [N+1:0] M       = 6'b001111,   // prime M
    parameter [N+1:0] M_INV   = 6'b010001    // -M^{-1} mod R
)(
    input  logic         clk,
    input  logic [N:0] A,     // 0 <= A < 2M
    input  logic [N:0] B,     // 0 <= B < 2M
    output logic [N:0]   C      // A*B*R^{-1} mod M
);

    //  full multiply 
    logic [2*N+1:0] T_full;
    logic [N+1:0]   T_L_s1;
    logic [N-1:0]   T_H_s1;

    multiply #(.N(N)) u_mul (
        .clk(clk), .a(A), .b(B),
        .T(T_full), .T_L(T_L_s1), .T_H(T_H_s1)
    );

    // find Q_L and D 
    logic [N+1:0] Q_L_s2, D_s2;

    logic [N+1:0] T_L_s2;
    logic [N-1:0] T_H_s2;

    always_ff @(posedge clk) begin
        T_L_s2 <= T_L_s1;
        T_H_s2 <= T_H_s1;
    end

    finding_q #(.N(N), .M_INV(M_INV)) u_findq (
        .clk(clk), .T_L(T_L_s1),
        .Q_L(Q_L_s2), .D(D_s2)
    );

    // high truncation 
    logic [N-1:0] S_H_s3;

    
    logic [N+1:0] T_L_s3;
    logic [N-1:0] T_H_s3;

    always_ff @(posedge clk) begin
        T_L_s3 <= T_L_s2;
        T_H_s3 <= T_H_s2;
    end

    high_truncation #(.N(N), .d(d), .M(M)) u_htrunc (
        .clk(clk), .Q_L(Q_L_s2), .D(D_s2),
        .S_H(S_H_s3)
    );


    final_result #(.N(N)) u_final (
        .clk(clk),
        .T_H(T_H_s3), .S_H(S_H_s3), .T_L(T_L_s3),
        .C(C)
    );

endmodule