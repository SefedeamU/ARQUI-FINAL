`timescale 1ns / 1ps
// fp_div.v  (Verilog-2001 limpio)
// IEEE-754 divide (paramétrico) con RNE. División entera del significando extendido.
// flags = {OVF, UDF, DBZ, INV, INX}
module fp_div #(parameter W=32, parameter E=8, parameter M=23) (
  input  wire [W-1:0] a,
  input  wire [W-1:0] b,
  input  wire [1:0]   rnd,     // 00 usado (RNE)
  output reg  [W-1:0] y,
  output reg  [4:0]   flags
);

  // Constantes
  localparam [E-1:0] EXP_MAX = (1<<E) - 1;
  localparam [E-1:0] BIAS    = (1<<(E-1)) - 1;

  // Desempaque
  wire sa = a[W-1];
  wire sb = b[W-1];
  wire [E-1:0] ea = a[W-2 : W-E-1];  // [30:23] en single, [14:10] en half
  wire [E-1:0] eb = b[W-2 : W-E-1];
  wire [M-1:0] fa = a[M-1:0];
  wire [M-1:0] fb = b[M-1:0];

  // Clasificación
  wire a_nan  = (ea==EXP_MAX) && (fa!=0);
  wire b_nan  = (eb==EXP_MAX) && (fb!=0);
  wire a_inf  = (ea==EXP_MAX) && (fa==0);
  wire b_inf  = (eb==EXP_MAX) && (fb==0);
  wire a_zero = (ea==0) && (fa==0);
  wire b_zero = (eb==0) && (fb==0);

  // Flags
  reg ovf, udf, dbz, inv, inx;

  // Significandos con bit oculto
  wire [M:0] ma = (ea==0) ? {1'b0, fa} : {1'b1, fa};
  wire [M:0] mb = (eb==0) ? {1'b0, fb} : {1'b1, fb};

  // Intermedios
  reg           sgn;
  reg [E:0]     exp_work;
  reg [M:0]     mant_work;
  reg [2:0]     grs;

  // División con precisión M+3 (para GRS)
  reg [M+3:0]   q;         // cociente (M+4 bits)
  reg [M+3:0]   rem;       // residuo
  reg [2*M+3:0] dividend;  // (M+1) << (M+3) = 2M+4 bits

  // RNE helpers (fix con M+2 bits)
  reg [M+1:0]   mant_ext;

  always @* begin
    // Defaults
    y   = {W{1'b0}};
    ovf = 1'b0; udf = 1'b0; dbz = 1'b0; inv = 1'b0; inx = 1'b0;

    // Casos especiales
    if (a_nan || b_nan || (a_inf && b_inf) || (a_zero && b_zero)) begin
      y   = {1'b0, {E{1'b1}}, {1'b1, {(M-1){1'b0}}}}; // qNaN
      inv = 1'b1;
    end
    else if (b_zero) begin
      y   = {sa^sb, {E{1'b1}}, {M{1'b0}}};  // +/-Inf
      dbz = 1'b1; inx = 1'b1;
    end
    else if (a_inf) begin
      y = {sa^sb, {E{1'b1}}, {M{1'b0}}};
    end
    else if (a_zero) begin
      y = {sa^sb, {E{1'b0}}, {M{1'b0}}};
    end
    else begin
      // signo y exponente preliminar
      sgn      = sa ^ sb;
      // cuidado con subnormales: ea==0 => usa 1 en vez de 0
      exp_work = (ea==0 ? 1 : ea) - (eb==0 ? 1 : eb) + BIAS;

      // Dividend = ma << (M+3)  (precisión para GRS)
      dividend = {ma, {(M+3){1'b0}}};
      q        = dividend / mb;
      rem      = dividend % mb;

      // ---------------- Normalización ----------------
      // q[M+3]==1  => cociente en [1,2): NO tocar exp
      // q[M+3]==0  => cociente en [0.5,1): desplazar izq (exp - 1)
      if (q[M+3]) begin
        mant_work = q[M+3 : 3];                       // (M+1) bits
        grs       = { q[2], q[1], (q[0] | (|rem)) };
      end else begin
        mant_work = q[M+2 : 2];
        grs       = { q[1], q[0], (|rem) };
        exp_work  = exp_work - 1;
      end

      // ---------------- RNE (fix M+2 bits) ----------------
      if (grs[2] && (grs[1] || grs[0] || mant_work[0])) begin
        mant_ext = {1'b0, mant_work} + {{(M+1){1'b0}},1'b1}; // (M+2) bits
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

      // ---- Forzar subnormal si exp==0 y el bit oculto quedó '1' ----
      if (exp_work=={(E+1){1'b0}} && mant_work[M]==1'b1) begin
        inx       = 1'b1;
        mant_work = {1'b0, mant_work[M:1]}; // oculto->fracción
      end

      // ---------------- Empaquetado y flags ----------------------
      if (exp_work[E]) begin
        y   = {sgn, {E{1'b1}}, {M{1'b0}}};   // Inf
        ovf = 1'b1; inx = 1'b1;
      end else if (exp_work=={(E+1){1'b0}} && mant_work[M-1:0]=={M{1'b0}}) begin
        y = {sgn, {E{1'b0}}, {M{1'b0}}};     // +0/-0
      end else if (exp_work=={(E+1){1'b0}} && mant_work[M-1:0]!={M{1'b0}}) begin
        y   = {sgn, {E{1'b0}}, mant_work[M-1:0]}; // subnormal
        udf = 1'b1; inx = 1'b1;
      end else begin
        y = {sgn, exp_work[E-1:0], mant_work[M-1:0]}; // normal
      end
    end

    flags = {ovf, udf, dbz, inv, inx};
  end
endmodule
