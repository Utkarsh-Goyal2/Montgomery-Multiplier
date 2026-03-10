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


// NLTM : NAF Low-part Truncated Multiplication
// Low-part truncation: only keep bits [N+1:0] of each product
// D = R - T_L = ~T_L + 1  (used later by NFHTM for error compensation)
module NLTM #(
    parameter N = 4,
    // NAF positive part of M'
    parameter [N+1:0] M_INV_POS  = 6'b010000,   // example: +16
    // NAF negative part of M'
    parameter [N+1:0] M_INV_NEG  = 6'b000001    // example: -1  => M'=15
)(
    input  logic         clk,
    input  logic [N+1:0] T_L,
    output logic [N+1:0] Q_L,
    output logic [N+1:0] D
);
    // accumulators for low-part truncated multiplication
    logic [N+2:0] pos_acc;   // one extra guard bit for borrowing
    logic [N+2:0] neg_acc;

    always_comb begin
        pos_acc = '0;
        neg_acc = '0;

        // Low-part truncated multiply: T_L * M_INV_POS
        // For each set bit in M_INV_POS, shift T_L left and accumulate
        // Only keep lower N+2 bits (truncation happens naturally by register width)
        for (int i = 0; i <= N+1; i++) begin
            if (M_INV_POS[i])
                pos_acc = pos_acc + (({1'b0, T_L} << i) & {{1{1'b0}}, {N+2{1'b1}}});
        end

        for (int i = 0; i <= N+1; i++) begin
            if (M_INV_NEG[i])
                neg_acc = neg_acc + (({1'b0, T_L} << i) & {{1{1'b0}}, {N+2{1'b1}}});
        end
    end

    always_ff @(posedge clk) begin
        Q_L <= ({1'b1, pos_acc[N+1:0]} - {1'b0, neg_acc[N+1:0]})[N+1:0];

        // D = R - T_L
        D   <= (~T_L) + 1'b1;
    end
endmodule


// NFHTM : NAF High-Part Truncated Multiplication
// U = Q_L ⋉_(N) Mpos  -  Q_L ⋉_(N) Mneg
//   dcal  = U[d-1:0]            (bottom d bits of U, the CEP region)
//   dreal = D[N+1 : N+2-d]      (top d bits of D)
//   Carry  condition: dcal[d-1]=1, dreal[d-1]=0, dcal[d-2:0] > dreal[d-2:0]  => S_H = U + 1
//   Borrow condition: dcal[d-1]=0, dreal[d-1]=1, dcal[d-2:0] < dreal[d-2:0]  => S_H = U - 1
//   Otherwise:                                                               => S_H = U
module NFHTM #(
    parameter N                 = 4,
    parameter d                 = 3,
    // NAF positive part of M
    parameter [N+1:0] M_POS     = 6'b010000,    // example: Mpos=16
    // NAF negative part of M
    parameter [N+1:0] M_NEG     = 6'b000001     // example: Mneg=1 => M=15
)(
    input  logic         clk,
    input  logic [N+1:0] Q_L,
    input  logic [N+1:0] D,
    output logic [N-1:0] S_H
);
    // Accumulators for high-part truncated multiplication
    // We need N+d bits: upper N bits are the MSP answer, lower d bits are CEP (dcal)
    logic [N+d-1:0] pos_acc;
    logic [N+d-1:0] neg_acc;
    logic [N+d-1:0] U_full;   // U = pos_acc - neg_acc

    logic [d-1:0]   d_cal;
    logic [d-1:0]   d_real;
    logic [N-1:0]   U_msp;    // upper N bits = MSP candidate answer

    always_comb begin
        pos_acc = '0;
        neg_acc = '0;

        // High-part truncated multiply: Q_L * M_POS
        // We want bits [(2N+2)-1 : N+2] of Q_L*M but shifted:
        // since Q_L is N+2 bits and M is N+2 bits, full product is 2N+4 bits
        // MSP = upper N bits = bits [2N+3 : N+4]  ... but we also need d CEP bits below that
        // So we accumulate bits [N+3+d-1 : N+4-d] — i.e. we keep N+d bits starting
        // from bit position (N+2-d) of the full product
        //
        // Concretely: for each set bit i in M_POS, contribution is Q_L << i
        // We extract bits [N+1+d : N+2] of that shifted value (N+d bits total)
        for (int i = 0; i <= N+1; i++) begin
            if (M_POS[i]) begin
                // full contribution at bit position i: Q_L[N+1:0] << i
                // we want bits [(N+2+d-1) : (N+2-0)] relative to bit 0 of full product
                // i.e. bits [N+d+1 : N+2] of (Q_L << i)
                // which equals Q_L >> (N+2 - d - ... )  -- handle per shift amount
                // Simpler: form the (2N+4)-bit product contribution, then slice
                logic [2*N+5:0] contrib;
                contrib = ({1'b0, Q_L} << i);
                // Slice out N+d bits starting at bit (N+2-d) of contrib
                pos_acc = pos_acc + contrib[N+1+d : N+2-0+0];
                // Note: contrib[N+1+d -: (N+d)] = contrib[N+1+d : 2]  for d=3,N=4
            end
        end

        for (int i = 0; i <= N+1; i++) begin
            if (M_NEG[i]) begin
                logic [2*N+5:0] contrib;
                contrib = ({1'b0, Q_L} << i);
                neg_acc = neg_acc + contrib[N+1+d : N+2-0+0];
            end
        end

        // U = Mpos part - Mneg part
        U_full = pos_acc - neg_acc;

        // CEP: bottom d bits of U
        d_cal  = U_full[d-1 : 0];

        // dreal: top d bits of D  (Algorithm 4 step 1: dreal = D[N+1 : N+2-d])
        d_real = D[N+1 -: d];

        // MSP candidate: upper N bits of U
        U_msp  = U_full[N+d-1 : d];
    end

    always_ff @(posedge clk) begin
        // Algorithm 4, steps 4-9
        // Carry:  dcal[d-1]=1, dreal[d-1]=0, dcal[d-2:0] > dreal[d-2:0]
        if (d_cal[d-1] & ~d_real[d-1] & (d_cal[d-2:0] > d_real[d-2:0]))
            S_H <= U_msp + 1'b1;

        // Borrow: dcal[d-1]=0, dreal[d-1]=1, dcal[d-2:0] < dreal[d-2:0]
        else if (~d_cal[d-1] & d_real[d-1] & (d_cal[d-2:0] < d_real[d-2:0]))
            S_H <= U_msp - 1'b1;

        // No error
        else
            S_H <= U_msp;
    end

endmodule




module final_result_opt #(
    parameter N = 4
)(
    input  logic         clk,
    input  logic [N-1:0] T_H,
    input  logic [N-1:0] S_H,
    input  logic         tl_zero,   // 1 when T_L == 0, pipelined from stage 1
    output logic [N:0]   C
);
    always_ff @(posedge clk) begin
        if (tl_zero)
            // T_L=0 => S_H=0 and carry=0 => C = T_H
            C <= {1'b0, T_H};
        else
            // T_L!=0 => carry always 1 => C = T_H + S_H + 1
            C <= {1'b0, T_H} + {1'b0, S_H} + 1'b1;
    end
endmodule



module top_HTMMM_NAF #(
    parameter N                  = 4,
    parameter d                  = 3,
    // NAF of M
    parameter [N+1:0] M_POS      = 6'b010000,   // Mpos
    parameter [N+1:0] M_NEG      = 6'b000001,   // Mneg  (M = Mpos - Mneg = 15)
    // NAF of M' = -M^{-1} mod R
    parameter [N+1:0] M_INV_POS  = 6'b010000,   // M'pos  (set correctly for your prime)
    parameter [N+1:0] M_INV_NEG  = 6'b000001    // M'neg
)(
    input  logic       clk,
    input  logic [N:0] A,          // 0 <= A < 2M
    input  logic [N:0] B,          // 0 <= B < 2M
    output logic [N:0] C           // A*B*R^{-1} mod M
);

    logic [2*N+1:0] T_full;
    logic [N+1:0]   T_L_s1;
    logic [N-1:0]   T_H_s1;
    logic           tl_zero_s1;    // 1 when T_L == 0

    multiply #(.N(N)) u_mul (
        .clk (clk),
        .a   ({1'b0, A}),
        .b   ({1'b0, B}),
        .T   (T_full),
        .T_L (T_L_s1),
        .T_H (T_H_s1)
    );

    // Register the zero flag in the same FF stage as multiply output
    // product[N+1:0] is T_L before it is registered inside multiply,
    // so we check the combinational product directly here
    logic [2*N+1:0] product_comb;
    assign product_comb = ({1'b0, A}) * ({1'b0, B});

    always_ff @(posedge clk) begin
        // Flag is 1 when the lower N+2 bits of the product are all zero
        tl_zero_s1 <= (product_comb[N+1:0] == '0);
    end

   
    logic [N+1:0] Q_L_s2, D_s2;
    logic [N-1:0] T_H_s2;
    logic         tl_zero_s2;

    always_ff @(posedge clk) begin
        T_H_s2     <= T_H_s1;
        tl_zero_s2 <= tl_zero_s1;
    end

    NLTM #(
        .N         (N),
        .M_INV_POS (M_INV_POS),
        .M_INV_NEG (M_INV_NEG)
    ) u_nltm (
        .clk (clk),
        .T_L (T_L_s1),
        .Q_L (Q_L_s2),
        .D   (D_s2)
    );

 
    logic [N-1:0] S_H_s3;
    logic [N-1:0] T_H_s3;
    logic         tl_zero_s3;

    always_ff @(posedge clk) begin
        T_H_s3     <= T_H_s2;
        tl_zero_s3 <= tl_zero_s2;
    end

    NFHTM #(
        .N     (N),
        .d     (d),
        .M_POS (M_POS),
        .M_NEG (M_NEG)
    ) u_nfhtm (
        .clk (clk),
        .Q_L (Q_L_s2),
        .D   (D_s2),
        .S_H (S_H_s3)
    );

 
    //   tl_zero=1  =>  C = T_H          (S_H=0, carry=0, bypass addition)
    //   tl_zero=0  =>  C = T_H + S_H + 1 (carry always 1 when T_L != 0)
   
    final_result_opt #(.N(N)) u_final (
        .clk    (clk),
        .T_H    (T_H_s3),
        .S_H    (S_H_s3),
        .tl_zero(tl_zero_s3),
        .C      (C)
    );

endmodule