// =============================================================
// multiply: registered product + split outputs + tl_zero flag
// =============================================================
module multiply #(parameter N = 4)(
    input  logic           clk,
    input  logic [N+1:0]   a,
    input  logic [N+1:0]   b,
    output logic [2*N+1:0] T,
    output logic [N+1:0]   T_L,
    output logic [N-1:0]   T_H,
    output logic           tl_zero
);
    logic [2*N+1:0] product;

    always_comb product = a * b;

    always_ff @(posedge clk) begin
        T       <= product;
        T_L     <= product[N+1:0];
        T_H     <= product[2*N+1 : N+2];
        tl_zero <= (product[N+1:0] == '0);
    end
endmodule


// =============================================================
// NLTM : NAF Low-part Truncated Multiplication
// Q_L = low N+2 bits of T_L * M'
// D   = -T_L mod R  (two's complement)
// =============================================================
module NLTM #(
    parameter N = 4,
    parameter [N+1:0] M_INV_POS = 6'b010001,
    parameter [N+1:0] M_INV_NEG = 6'b000000
)(
    input  logic         clk,
    input  logic [N+1:0] T_L,
    output logic [N+1:0] Q_L,
    output logic [N+1:0] D
);
    // FIX: Use wide accumulators so carry propagates correctly.
    // Max value of low-part truncated product is (2^(N+2)-1)^2 truncated to N+2 bits,
    // but we only accumulate N+2 set-bit contributions each shifting T_L by at most N+1,
    // so N+2 + N+1 + log2(N+2) extra bits is safe. Use 2*(N+2) bits.
    localparam AW = 2*(N+2);

    logic [AW-1:0] pos_acc;
    logic [AW-1:0] neg_acc;

    always_comb begin
        pos_acc = '0;
        neg_acc = '0;
        for (int i = 0; i <= N+1; i++) begin
            if (M_INV_POS[i])
                // FIX: add full-width shifted value; truncation to N+2 bits happens at register
                pos_acc = pos_acc + (AW'({1'b0, T_L}) << i);
        end
        for (int i = 0; i <= N+1; i++) begin
            if (M_INV_NEG[i])
                neg_acc = neg_acc + (AW'({1'b0, T_L}) << i);
        end
    end

    always_ff @(posedge clk) begin
        // Keep only lower N+2 bits (truncation) after subtraction
        Q_L <= pos_acc[N+1:0] - neg_acc[N+1:0];
        D   <= (~T_L) + 1'b1;   // D = -T_L mod R
    end
endmodule


// =============================================================
// NFHTM : NAF High-Part Truncated Multiplication
// S_H = upper N bits of Q_L * M, with carry/borrow correction
// =============================================================
module NFHTM #(
    parameter N             = 4,
    parameter d             = 3,
    parameter [N+1:0] M_POS = 6'b010000,
    parameter [N+1:0] M_NEG = 6'b000001
)(
    input  logic         clk,
    input  logic [N+1:0] Q_L,
    input  logic [N+1:0] D,
    output logic [N-1:0] S_H
);
    // Window: bits [BASE .. BASE+WIN_W-1] of the full product, where
    //   BASE  = N+2-d   (lowest bit index we keep)
    //   WIN_W = N+d     (N bits MSP + d bits CEP)
    localparam BASE  = N + 2 - d;
    localparam WIN_W = N + d;

    // FIX: use proper wide accumulators and add full N+2 bit Q_L shifted into window.
    // Max contribution per set bit of M: Q_L << i, up to N+1+N+1 = 2N+2 bits wide.
    // We only care about WIN_W bits starting at BASE, so accumulate WIN_W+guard bits.
    localparam AW = WIN_W + 4;  // a few guard bits for overflow safety

    logic [AW-1:0] pos_acc;
    logic [AW-1:0] neg_acc;
    logic [WIN_W-1:0] U_full;
    logic [AW-1:0]   diff_acc;  // temp for subtraction

    logic [d-1:0]  d_cal;
    logic [d-1:0]  d_real;
    logic [N-1:0]  U_msp;

    always_comb begin
        pos_acc  = '0;
        neg_acc  = '0;
        diff_acc = '0;

        // FIX: accumulate full Q_L<<i shifted into the window by dividing by 2^BASE.
        // Since BASE is a localparam (constant), the >> BASE synthesizes to a wire slice.
        for (int i = 0; i <= N+1; i++) begin
            if (M_POS[i])
                pos_acc = pos_acc + ((AW'(Q_L) << i) >> BASE);
        end

        for (int i = 0; i <= N+1; i++) begin
            if (M_NEG[i])
                neg_acc = neg_acc + ((AW'(Q_L) << i) >> BASE);
        end

        diff_acc = pos_acc - neg_acc;
        U_full   = diff_acc[WIN_W-1:0];

        d_cal  = U_full[d-1:0];
        d_real = D[N+1 -: d];
        U_msp  = U_full[WIN_W-1:d];
    end

    always_ff @(posedge clk) begin
        // Carry:  dcal MSB=1, dreal MSB=0, lower bits dcal > dreal
        if (d_cal[d-1] & ~d_real[d-1] & (d_cal[d-2:0] > d_real[d-2:0]))
            S_H <= U_msp + 1'b1;
        // Borrow: dcal MSB=0, dreal MSB=1, lower bits dcal < dreal
        else if (~d_cal[d-1] & d_real[d-1] & (d_cal[d-2:0] < d_real[d-2:0]))
            S_H <= U_msp - 1'b1;
        else
            S_H <= U_msp;
    end
endmodule


// =============================================================
// final_result_opt: T_H + S_H + carry => raw Montgomery result
// FIX: output is [N:0] to hold the full sum without truncation
// =============================================================
module final_result_opt #(parameter N = 4)(
    input  logic         clk,
    input  logic [N-1:0] T_H,
    input  logic [N-1:0] S_H,
    input  logic         tl_zero,
    output logic [N:0]   C        // N+1 bits: result can be up to 2M-1
);
    always_ff @(posedge clk) begin
        if (tl_zero)
            C <= {1'b0, T_H};
        else
            C <= {1'b0, T_H} + {1'b0, S_H} + 1'b1;
    end
endmodule


// =============================================================
// top_HTMMM_NAF: full pipeline
//   Stage 1      : multiply A*B
//   Stage 2      : NLTM (low-part Q_L, D)
//   Stage 3      : NFHTM (high-part S_H)
//   Stage 4      : final_result_opt => C_raw = A*B*R^-1 mod M (unreduced)
//   Stage 5      : modular reduction => C_red in [0,M)
//   Stages 6-9   : second MMM(C_red, R2_MODM) => C2_raw = A*B mod M (unreduced)
//   Stage 10     : modular reduction => C in [0,M)
//
// Total latency: 10 clock cycles
// =============================================================
module top_HTMMM_NAF #(
    parameter N                  = 4,
    parameter d                  = 3,
    parameter [N+1:0] M_POS      = 6'b010000,   // NAF+ of M
    parameter [N+1:0] M_NEG      = 6'b000001,   // NAF- of M  => M=15
    parameter [N+1:0] M_INV_POS  = 6'b010001,   // NAF+ of M' = -M^{-1} mod R
    parameter [N+1:0] M_INV_NEG  = 6'b000000,   // NAF- of M'
    parameter [N-1:0] R2_MODM    = 4'd1         // R^2 mod M  (R=2^(N+2)=64, R^2 mod 15=1)
)(
    input  logic         clk,
    input  logic [N-1:0] A,
    input  logic [N-1:0] B,
    output logic [N-1:0] C
);
    localparam [N:0] M_val = M_POS[N:0] - M_NEG[N:0];  // M as N+1-bit value

    // -------------------------
    // STAGE 1: Multiply A * B
    // -------------------------
    logic [2*N+1:0] T_full;
    logic [N+1:0]   T_L_s1;
    logic [N-1:0]   T_H_s1;
    logic           tl_zero_s1;

    multiply #(.N(N)) u_mul (
        .clk     (clk),
        .a       ({2'b00, A}),
        .b       ({2'b00, B}),
        .T       (T_full),
        .T_L     (T_L_s1),
        .T_H     (T_H_s1),
        .tl_zero (tl_zero_s1)
    );

    // -------------------------
    // STAGE 2: NLTM
    // -------------------------
    logic [N+1:0] Q_L_s2, D_s2;
    logic [N-1:0] T_H_s2;
    logic         tl_zero_s2;

    always_ff @(posedge clk) begin
        T_H_s2     <= T_H_s1;
        tl_zero_s2 <= tl_zero_s1;
    end

    NLTM #(.N(N), .M_INV_POS(M_INV_POS), .M_INV_NEG(M_INV_NEG)) u_nltm (
        .clk (clk),
        .T_L (T_L_s1),
        .Q_L (Q_L_s2),
        .D   (D_s2)
    );

    // -------------------------
    // STAGE 3: NFHTM
    // -------------------------
    logic [N-1:0] S_H_s3;
    logic [N-1:0] T_H_s3;
    logic         tl_zero_s3;

    always_ff @(posedge clk) begin
        T_H_s3     <= T_H_s2;
        tl_zero_s3 <= tl_zero_s2;
    end

    NFHTM #(.N(N), .d(d), .M_POS(M_POS), .M_NEG(M_NEG)) u_nfhtm (
        .clk (clk),
        .Q_L (Q_L_s2),
        .D   (D_s2),
        .S_H (S_H_s3)
    );

    // -------------------------
    // STAGE 4: Combine => A*B*R^-1 (unreduced)
    // -------------------------
    logic [N:0] C_raw;   // FIX: N+1 bits to hold full sum

    final_result_opt #(.N(N)) u_final (
        .clk     (clk),
        .T_H     (T_H_s3),
        .S_H     (S_H_s3),
        .tl_zero (tl_zero_s3),
        .C       (C_raw)
    );

    // -------------------------
    // STAGE 5: Reduce C_raw into [0, M)
    // -------------------------
    logic [N-1:0] C_red;

    always_ff @(posedge clk) begin
        if (C_raw >= M_val)
            C_red <= C_raw[N-1:0] - M_val[N-1:0];
        else
            C_red <= C_raw[N-1:0];
    end

    // -------------------------
    // STAGES 6-9: Second MMM: MMM(C_red, R2_MODM) = A*B mod M
    // -------------------------
    logic [2*N+1:0] T2_full;
    logic [N+1:0]   T2_L_s1;
    logic [N-1:0]   T2_H_s1;
    logic           tl2_zero_s1;

    multiply #(.N(N)) u_mul2 (
        .clk     (clk),
        .a       ({2'b00, C_red}),
        .b       ({2'b00, R2_MODM}),
        .T       (T2_full),
        .T_L     (T2_L_s1),
        .T_H     (T2_H_s1),
        .tl_zero (tl2_zero_s1)
    );

    logic [N+1:0] Q2_L_s2, D2_s2;
    logic [N-1:0] T2_H_s2;
    logic         tl2_zero_s2;

    always_ff @(posedge clk) begin
        T2_H_s2     <= T2_H_s1;
        tl2_zero_s2 <= tl2_zero_s1;
    end

    NLTM #(.N(N), .M_INV_POS(M_INV_POS), .M_INV_NEG(M_INV_NEG)) u_nltm2 (
        .clk (clk),
        .T_L (T2_L_s1),
        .Q_L (Q2_L_s2),
        .D   (D2_s2)
    );

    logic [N-1:0] S2_H_s3;
    logic [N-1:0] T2_H_s3;
    logic         tl2_zero_s3;

    always_ff @(posedge clk) begin
        T2_H_s3     <= T2_H_s2;
        tl2_zero_s3 <= tl2_zero_s2;
    end

    NFHTM #(.N(N), .d(d), .M_POS(M_POS), .M_NEG(M_NEG)) u_nfhtm2 (
        .clk (clk),
        .Q_L (Q2_L_s2),
        .D   (D2_s2),
        .S_H (S2_H_s3)
    );

    logic [N:0] C2_raw;   // FIX: N+1 bits

    final_result_opt #(.N(N)) u_final2 (
        .clk     (clk),
        .T_H     (T2_H_s3),
        .S_H     (S2_H_s3),
        .tl_zero (tl2_zero_s3),
        .C       (C2_raw)
    );

    // -------------------------
    // STAGE 10: Final reduction => C in [0, M)
    // -------------------------
    always_ff @(posedge clk) begin
        if (C2_raw >= M_val)
            C <= C2_raw[N-1:0] - M_val[N-1:0];
        else
            C <= C2_raw[N-1:0];
    end

endmodule