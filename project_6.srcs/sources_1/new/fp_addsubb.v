`timescale 1ns / 1ps
// fp_addsub.v  (Verilog-2001 limpio)
// IEEE-754 add/sub (paramétrico) con RNE (round-to-nearest-even).
// flags = {OVF, UDF, DBZ, INV, INX}
module fp_addsub #(parameter W=32, parameter E=8, parameter M=23) (
  input  wire [W-1:0] a,
  input  wire [W-1:0] b,
  input  wire         is_sub,      // 0=ADD, 1=SUB => a + (-b)
  input  wire [1:0]   rnd,         // 00 usado (RNE)
  output reg  [W-1:0] y,
  output reg  [4:0]   flags
);

  // ---------------- Constantes ----------------
  localparam [E-1:0] EXP_MAX = ((1<<E) - 1);
  localparam [E-1:0] BIAS    = ((1<<(E-1)) - 1);

  // ---------------- Desempaque ----------------
  wire sa = a[W-1];
  wire sb = b[W-1];
  wire [E-1:0] ea = a[W-2 -: E];
  wire [E-1:0] eb = b[W-2 -: E];
  wire [M-1:0] fa = a[M-1:0];
  wire [M-1:0] fb = b[M-1:0];

  // ---------------- Clasificación -------------
  wire a_nan  = (ea==EXP_MAX) && (fa!=0);
  wire b_nan  = (eb==EXP_MAX) && (fb!=0);
  wire a_inf  = (ea==EXP_MAX) && (fa==0);
  wire b_inf  = (eb==EXP_MAX) && (fb==0);
  wire a_zero = (ea==0) && (fa==0);
  wire b_zero = (eb==0) && (fb==0);

  // Efecto de resta: invierte signo de b
  wire sb_eff = is_sub ? ~sb : sb;

  // Significandos con bit oculto
  wire [M:0] ma = (ea==0) ? {1'b0, fa} : {1'b1, fa};
  wire [M:0] mb = (eb==0) ? {1'b0, fb} : {1'b1, fb};

  // Alineación por exponente
  wire [E:0] ea_ext = {1'b0, ea};
  wire [E:0] eb_ext = {1'b0, eb};

  wire       a_is_bigger = (ea_ext > eb_ext) || ((ea_ext==eb_ext) && (ma >= mb));
  wire [E:0] exp_big  = a_is_bigger ? ea_ext : eb_ext;
  wire [E:0] exp_sml  = a_is_bigger ? eb_ext : ea_ext;
  wire [M:0] man_big0 = a_is_bigger ? ma     : mb;
  wire [M:0] man_sml0 = a_is_bigger ? mb     : ma;
  wire       sgn_big  = a_is_bigger ? sa     : sb_eff;
  wire       sgn_sml  = a_is_bigger ? sb_eff : sa;

  wire [E:0] dexp = exp_big - exp_sml; // diferencia de exponentes

  // ---------------- Registros auxiliares ----------------
  reg [M+3:0] man_big, man_sml, man_sml_pre;
  reg         sticky_shift;
  integer     i;

  reg [M+4:0] sum_ext;
  reg         same_sign;
  reg         res_sign;

  reg [E:0]   exp_work;
  reg [M:0]   mant_work;      // [hidden | frac]
  reg [2:0]   grs;            // {G,R,S}

  reg [M+4:0] tmp;
  integer     sh;
  integer     k;

  // RNE helpers (fix con M+2 bits)
  reg [M+1:0] mant_ext;

  // Flags
  reg ovf, udf, dbz, inv, inx;

  // ---------------- Lógica combinacional principal ----------------
  always @* begin
    // Defaults
    y   = {W{1'b0}};
    ovf = 1'b0; udf = 1'b0; dbz = 1'b0; inv = 1'b0; inx = 1'b0;

    // Casos especiales (NaN/Inf/0)
    if (a_nan || b_nan) begin
      y   = {1'b0, {E{1'b1}}, {1'b1, {(M-1){1'b0}}}}; // qNaN
      inv = 1'b1;
    end
    else if (a_inf && b_inf) begin
      if (sa ^ sb_eff) begin
        y   = {1'b0, {E{1'b1}}, {1'b1, {(M-1){1'b0}}}}; // qNaN
        inv = 1'b1;
      end else begin
        y   = {sa, {E{1'b1}}, {M{1'b0}}};               // +/-Inf
      end
    end
    else if (a_inf) begin
      y = {sa, {E{1'b1}}, {M{1'b0}}};
    end
    else if (b_inf) begin
      y = {sb_eff, {E{1'b1}}, {M{1'b0}}};
    end
    else if (a_zero && b_zero) begin
      y = {(sa ^ sb_eff), {E{1'b0}}, {M{1'b0}}};
    end
    else begin
      // ---------- Alineación con sticky ----------
      man_big     = {man_big0, 3'b000};
      man_sml_pre = {man_sml0, 3'b000};

      if (dexp >= (M+4)) begin
        man_sml      = {(M+4){1'b0}};
        sticky_shift = |man_sml_pre;
      end else begin
        man_sml      = man_sml_pre >> dexp;
        sticky_shift = 1'b0;
        if (dexp != 0) begin
          for (k=0; k<dexp; k=k+1) begin
            sticky_shift = sticky_shift | man_sml_pre[k];
          end
        end
      end
      man_sml[0] = man_sml[0] | sticky_shift;

      // ---------- Operación por magnitud ----------
      same_sign = (sgn_big == sgn_sml);
      if (same_sign) begin
        sum_ext  = {1'b0, man_big} + {1'b0, man_sml};
        res_sign = sgn_big;
      end else begin
        sum_ext  = {1'b0, man_big} - {1'b0, man_sml};
        res_sign = (man_big >= man_sml) ? sgn_big : sgn_sml;
      end

      // Cero exacto
      if (sum_ext=={(M+5){1'b0}}) begin
        y = {res_sign, {E{1'b0}}, {M{1'b0}}};
      end else begin
        // ---------- Normalización ----------
        exp_work  = exp_big;

        if (sum_ext[M+4]) begin
          mant_work = sum_ext[M+4:4]; // (M+1) bits
          grs       = {sum_ext[3], sum_ext[2], (sum_ext[1] | sum_ext[0])};
          exp_work  = exp_big + 1;
        end else begin
          tmp = sum_ext;
          for (sh=0; sh<(M+3); sh=sh+1) begin
            if (tmp[M+3]==1'b1) begin
              // listo
            end else if (exp_work!=0) begin
              tmp      = tmp << 1;
              exp_work = exp_work - 1;
            end
          end
          mant_work = tmp[M+3:3];               // (M+1) bits
          grs       = {tmp[2], tmp[1], tmp[0]};
        end

        // ---------- RNE (fix M+2 bits) ----------
        if (grs[2] && (grs[1] || grs[0] || mant_work[0])) begin
          mant_ext = {1'b0, mant_work} + {{(M+1){1'b0}},1'b1}; // (M+2) bits
          inx = 1'b1;
          if (mant_ext[M+1]) begin
            // overflow real de mantisa tras redondeo
            mant_work = {1'b1, mant_ext[M+1:2]};
            exp_work  = exp_work + 1;
          end else begin
            mant_work = mant_ext[M:0];
          end
        end else begin
          inx = (grs[2] | grs[1] | grs[0]);
        end

        // ---------- Empaquetado y flags ----------
        if (exp_work[E] || (exp_work[E-1:0] == EXP_MAX)) begin
          y   = {res_sign, {E{1'b1}}, {M{1'b0}}}; // +/-Inf
          ovf = 1'b1;
          inx = 1'b1;
        end else if (exp_work=={(E+1){1'b0}} && mant_work[M-1:0]=={M{1'b0}}) begin
          y = {res_sign, {E{1'b0}}, {M{1'b0}}};
        end else if (exp_work=={(E+1){1'b0}} && mant_work[M-1:0]!={M{1'b0}}) begin
          y   = {res_sign, {E{1'b0}}, mant_work[M-1:0]}; // subnormal
          udf = 1'b1; inx = 1'b1;
        end else begin
          y = {res_sign, exp_work[E-1:0], mant_work[M-1:0]};
        end
      end
    end

    flags = {ovf, udf, dbz, inv, inx};
  end

endmodule
