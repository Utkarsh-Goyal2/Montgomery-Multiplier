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
    parameter [N+1:0] M_INV_POS  = 6'b010001,
    parameter [N+1:0] M_INV_NEG  = 6'b000000
)(
    input  logic         clk,
    input  logic [N+1:0] T_L,
    output logic [N+1:0] Q_L,
    output logic [N+1:0] D
);
    // accumulators for low-part truncated multiplication
    logic [N+2:0] pos_acc;   // one extra guard bit for borrowing
    logic [N+2:0] neg_acc;
    logic [N+2:0] q_temp;

    always @* begin
        pos_acc = '0;
        neg_acc = '0;
        q_temp  = '0;

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

        q_temp = {1'b1, pos_acc[N+1:0]} - {1'b0, neg_acc[N+1:0]};
    end

    always_ff @(posedge clk) begin
        Q_L <= q_temp[N+1:0];

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

    integer i, j, pos;

    // use always @* for better Icarus compatibility
    always @* begin
        pos_acc = '0;
        neg_acc = '0;
        U_full  = '0;
        d_cal   = '0;
        d_real  = '0;
        U_msp   = '0;

        for (i = 0; i <= N+1; i = i + 1) begin
            if (M_POS[i]) begin
                for (j = 0; j <= N+1; j = j + 1) begin
                    pos = j + i;
                    // only accumulate if this lands in MSP+CEP window [2N+3 : N+4-d]
                    if (pos >= (N+2-d)) begin
                        pos_acc[pos - (N+2-d)] = pos_acc[pos - (N+2-d)] + Q_L[j];
                    end
                end
            end
        end

        for (i = 0; i <= N+1; i = i + 1) begin
            if (M_NEG[i]) begin
                for (j = 0; j <= N+1; j = j + 1) begin
                    pos = j + i;
                    if (pos >= (N+2-d)) begin
                        neg_acc[pos - (N+2-d)] = neg_acc[pos - (N+2-d)] + Q_L[j];
                    end
                end
            end
        end

        U_full = pos_acc - neg_acc;

        // CEP = bottom d bits of accumulator (positions [N+3 : N+4-d] of full product)
        d_cal  = U_full[d-1 : 0];

        // dreal from D
        d_real = D[N+1 -: d];

        // MSP = upper N bits of accumulator (positions [2N+3 : N+4] of full product)
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
    parameter [N+1:0] M_INV_POS  = 6'b010001,   // M'pos = 17
    parameter [N+1:0] M_INV_NEG  = 6'b000000    // M'neg = 0
)(
    input  logic         clk,
    input  logic [N-1:0] A,          // 0 <= A < 2M
    input  logic [N-1:0] B,          // 0 <= B < 2M
    output logic [N:0] C           // final reduced Montgomery result
);

    logic [2*N+1:0] T_full;
    logic [N+1:0]   T_L_s1;
    logic [N-1:0]   T_H_s1;
    logic           tl_zero_s1;

    multiply #(.N(N)) u_mul (
        .clk (clk),
        .a   ({2'b00, A}),
        .b   ({2'b00, B}),
        .T   (T_full),
        .T_L (T_L_s1),
        .T_H (T_H_s1)
    );

    // Register zero flag aligned with stage 1 outputs
    logic [2*N+1:0] product_comb;
    assign product_comb = ({2'b00, A}) * ({2'b00, B});

    always_ff @(posedge clk) begin
        tl_zero_s1 <= (product_comb[N+1:0] == '0);
    end

    // Stage 2 pipeline
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

    // Stage 3 pipeline
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

        // Stage 4: raw result in [0, 2M)
    logic [N:0] C_raw;

    final_result_opt #(.N(N)) u_final (
        .clk    (clk),
        .T_H    (T_H_s3),
        .S_H    (S_H_s3),
        .tl_zero(tl_zero_s3),
        .C      (C_raw)
    );

    // Stage 5: final conditional subtraction by M
    localparam logic [N:0] M_val = M_POS[N:0] - M_NEG[N:0];
    logic [N:0] C_red;

    always_ff @(posedge clk) begin
        if (C_raw >= M_val)
            C_red <= C_raw - M_val;
        else
            C_red <= C_raw;
    end

    // Stage 6: convert Montgomery result back to normal result
    // Here R = 64 and M = 15, so R mod M = 4
    logic [N+2:0] C_times_R;
    logic [N:0]   C_norm;

    always_comb begin
        C_times_R = C_red << 2;
        C_norm    = C_times_R % M_val;
    end

    assign C = C_norm;

endmodule
