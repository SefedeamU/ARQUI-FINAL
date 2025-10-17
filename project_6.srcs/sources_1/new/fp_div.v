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

  // Desempaque (sin [-:] de SV)
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
  reg [M+3:0]   rem;       // residuo (guardado en mismo ancho por comodidad)
  reg [2*M+3:0] dividend;  // (M+1) << (M+3) = 2M+4 bits

  // Auxiliares para redondeo
  reg [M:0] mant_plus1;
  reg       carry_round;

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
      exp_work = (ea==0 ? 1 : ea) - (eb==0 ? 1 : eb) + BIAS;

      // Dividend = ma << (M+3)
      dividend = {ma, {(M+3){1'b0}}};
      q        = dividend / mb;
      rem      = dividend % mb;

      // Normalización y GRS SIN índices "M±const-M" (evita error 10-1219)
      // Caso A: 1.xxxxx -> MSB en q[M+3]
      if (q[M+3]) begin
        // Mantisa = q[M+3:3] (M+1 bits), G=q[2], R=q[1], S=q[0]|(rem!=0)
        mant_work = q[M+3 : 3];
        grs       = { q[2], q[1], (q[0] | (|rem)) };
        exp_work  = exp_work + 1;
      end else begin
        // Caso B: 0.1xxxx -> tomar q[M+2:2]; G=q[1], R=q[0], S=(rem!=0)
        mant_work = q[M+2 : 2];
        grs       = { q[1], q[0], (|rem) };
        // exp_work se mantiene
      end

      // RNE
      if (grs[2] && (grs[1] || grs[0] || mant_work[0])) begin
        mant_plus1  = mant_work + {{M{1'b0}},1'b1};
        carry_round = mant_plus1[M];
        mant_work   = mant_plus1;
        inx         = 1'b1;
        if (carry_round) begin
          mant_work = {1'b1, mant_work[M:1]};
          exp_work  = exp_work + 1;
        end
      end else begin
        inx = grs[2] | grs[1] | grs[0];
      end

      // Empaquetado y flags
      if (exp_work[E]) begin
        y   = {sgn, {E{1'b1}}, {M{1'b0}}};
        ovf = 1'b1; inx = 1'b1;
      end else if (exp_work=={(E+1){1'b0}} && mant_work[M-1:0]=={M{1'b0}}) begin
        y = {sgn, {E{1'b0}}, {M{1'b0}}};
      end else if (exp_work=={(E+1){1'b0}} && mant_work[M-1:0]!={M{1'b0}}) begin
        y   = {sgn, {E{1'b0}}, mant_work[M-1:0]};
        udf = 1'b1; inx = 1'b1;
      end else begin
        y = {sgn, exp_work[E-1:0], mant_work[M-1:0]};
      end
    end

    flags = {ovf, udf, dbz, inv, inx};
  end
endmodule