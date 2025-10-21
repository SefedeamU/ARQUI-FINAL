`timescale 1ns / 1ps
// fp_mul.v
// IEEE-754 multiply (paramétrico) con RNE.
// flags = {OVF, UDF, DBZ, INV, INX}
module fp_mul #(parameter W=32, parameter E=8, parameter M=23) (
  input  wire [W-1:0] a,
  input  wire [W-1:0] b,
  input  wire [1:0]   rnd,     // 00 usado (RNE)
  output reg  [W-1:0] y,
  output reg  [4:0]   flags
);
  localparam [E-1:0] EXP_MAX = (1<<E) - 1;
  localparam [E-1:0] BIAS    = (1<<(E-1)) - 1;

  wire sa = a[W-1];
  wire sb = b[W-1];
  wire [E-1:0] ea = a[W-2 -: E];
  wire [E-1:0] eb = b[W-2 -: E];
  wire [M-1:0] fa = a[M-1:0];
  wire [M-1:0] fb = b[M-1:0];

  wire a_nan=(ea==EXP_MAX)&&(fa!=0);
  wire b_nan=(eb==EXP_MAX)&&(fb!=0);
  wire a_inf=(ea==EXP_MAX)&&(fa==0);
  wire b_inf=(eb==EXP_MAX)&&(fb==0);
  wire a_zero=(ea==0)&&(fa==0);
  wire b_zero=(eb==0)&&(fb==0);

  reg ovf, udf, dbz, inv, inx;

  // Significandos con bit oculto
  wire [M:0] ma = (ea==0) ? {1'b0, fa} : {1'b1, fa};
  wire [M:0] mb = (eb==0) ? {1'b0, fb} : {1'b1, fb};

  // Producto de (M+1)x(M+1)
  reg [2*M+1:0] prod;  // 2*(M+1) bits
  reg [E:0]     exp_work;
  reg           sgn;

  // Normalización + GRS
  reg [M:0]    mant_work;
  reg [2:0]    grs;

  // RNE helpers (fix con M+2 bits)
  reg [M+1:0]  mant_ext;

  always @* begin
    // Defaults
    y   = {W{1'b0}};
    ovf = 1'b0; udf = 1'b0; dbz = 1'b0; inv = 1'b0; inx = 1'b0;

    // Casos especiales
    if (a_nan || b_nan || (a_zero && b_inf) || (a_inf && b_zero)) begin
      y   = {1'b0, {E{1'b1}}, {1'b1, {(M-1){1'b0}}}}; // qNaN
      inv = 1'b1;
    end
    else if (a_inf || b_inf) begin
      y = {sa^sb, {E{1'b1}}, {M{1'b0}}};
    end
    else if (a_zero || b_zero) begin
      y = {sa^sb, {E{1'b0}}, {M{1'b0}}};
    end
    else begin
      // Producto y exponente
      prod     = ma * mb;         // 2*M+2 bits
      sgn      = sa ^ sb;
      exp_work = (ea==0 ? 1 : ea) + (eb==0 ? 1 : eb) - BIAS;

      // Normalización (dos casos)
      if (prod[2*M+1]) begin
        // 1.xxx -> tomar [2M+1: M+1]
        mant_work = prod[2*M+1 : M+1];
        grs       = {prod[M], prod[M-1], |prod[M-2:0]};
        exp_work  = exp_work + 1;
      end else begin
        // 0.1xx -> tomar [2M : M]
        mant_work = prod[2*M : M];
        grs       = {prod[M-1], prod[M-2], |prod[M-3:0]};
      end

      // RNE (fix M+2 bits)
      if (grs[2] && (grs[1] || grs[0] || mant_work[0])) begin
        mant_ext = {1'b0, mant_work} + {{(M+1){1'b0}},1'b1};
        inx = 1'b1;
        if (mant_ext[M+1]) begin
          mant_work = {1'b1, mant_ext[M+1:2]};
          exp_work  = exp_work + 1;
        end else begin
          mant_work = mant_ext[M:0];
        end
      end else begin
        inx = grs[2] | grs[1] | grs[0];
      end

      // Empaquetado y flags
      if (exp_work[E] || (exp_work[E-1:0] == EXP_MAX)) begin
        y   = {sgn, {E{1'b1}}, {M{1'b0}}}; // Inf
        ovf = 1'b1; inx = 1'b1;
      end else if (exp_work=={(E+1){1'b0}} && mant_work[M-1:0]=={M{1'b0}}) begin
        y = {sgn, {E{1'b0}}, {M{1'b0}}};
      end else if (exp_work=={(E+1){1'b0}} && mant_work[M-1:0]!={M{1'b0}}) begin
        y   = {sgn, {E{1'b0}}, mant_work[M-1:0]}; // subnormal
        udf = 1'b1; inx = 1'b1;
      end else begin
        y = {sgn, exp_work[E-1:0], mant_work[M-1:0]};
      end
    end

    flags = {ovf, udf, dbz, inv, inx};
  end
endmodule
