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

  wire [E:0] dexp = exp_big - exp_sml; // diferencia de exponentes (0..255 típico en single)

  // ---------------- Registros auxiliares (declarados FUERA de bloques) ----
  // Mantisas extendidas para GRS (M+4 bits) y sumador extendido (M+5)
  reg [M+3:0] man_big, man_sml, man_sml_pre;
  reg         sticky_shift;
  integer     i;

  reg [M+4:0] sum_ext;        // resultado magnitud (con carry)
  reg         same_sign;
  reg         res_sign;

  // Normalización
  reg [E:0]   exp_work;
  reg [M:0]   mant_work;      // [hidden | frac]
  reg [2:0]   grs;            // {G,R,S}

  // Tmp para normalizar por la izquierda
  reg [M+4:0] tmp;
  integer     sh;
  integer     k;

  // Rounding helpers sin concatenaciones
  reg [M:0]   mant_plus1;
  reg         carry_round;

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
      // +Inf + (-Inf) = NaN
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
      // 0 (+/-) 0 -> 0 con XOR de signos (convención simple)
      y = {(sa ^ sb_eff), {E{1'b0}}, {M{1'b0}}};
    end
    else begin
      // ---------- Alineación con sticky (sin selects variables SV) ----------
      man_big     = {man_big0, 3'b000};
      man_sml_pre = {man_sml0, 3'b000};

      if (dexp >= (M+4)) begin
        man_sml      = {(M+4){1'b0}};
        sticky_shift = |man_sml_pre; // se pierde todo
      end else begin
        man_sml      = man_sml_pre >> dexp; // shift variable OK en Verilog
        // OR de los bits perdidos: 0..(dexp-1)
        sticky_shift = 1'b0;
        if (dexp != 0) begin
          for (k=0; k<dexp; k=k+1) begin
            sticky_shift = sticky_shift | man_sml_pre[k];
          end
        end
      end
      // S (sticky) se pega en LSB
      man_sml[0] = man_sml[0] | sticky_shift;

      // ---------- Operación por magnitud ----------
      same_sign = (sgn_big == sgn_sml);
      if (same_sign) begin
        sum_ext  = {1'b0, man_big} + {1'b0, man_sml};
        res_sign = sgn_big;
      end else begin
        sum_ext  = {1'b0, man_big} - {1'b0, man_sml};
        // signo del mayor en magnitud
        res_sign = (man_big >= man_sml) ? sgn_big : sgn_sml;
      end

      // Cero exacto
      if (sum_ext=={(M+5){1'b0}}) begin
        y = {res_sign, {E{1'b0}}, {M{1'b0}}};
      end else begin
        // ---------- Normalización desde sum_ext [M+4:0] ----------
        exp_work  = exp_big;

        // Carry alto (bit M+4 = 1) -> ya está por arriba, shift der 1 implícito
        if (sum_ext[M+4]) begin
          mant_work = sum_ext[M+4:4];                           // (M+1) bits
          grs       = {sum_ext[3], sum_ext[2], (sum_ext[1] | sum_ext[0])};
          exp_work  = exp_big + 1;
        end else begin
          // Desplazar a la izquierda hasta que el bit en M+3 sea 1 o exp llegue a 0
          tmp = sum_ext;
          for (sh=0; sh<(M+3); sh=sh+1) begin
            if (tmp[M+3]==1'b1) begin
              // nada
            end else if (exp_work!=0) begin
              tmp      = tmp << 1;
              exp_work = exp_work - 1;
            end
          end
          mant_work = tmp[M+3:3];               // (M+1) bits
          grs       = {tmp[2], tmp[1], tmp[0]}; // G,R,S
        end

        // ---------- RNE: G=grs[2], R=grs[1], S=grs[0] ----------
        // Incrementa si G=1 y (R=1 o S=1 o LSB=1)
        if (grs[2] && (grs[1] || grs[0] || mant_work[0])) begin
          mant_plus1   = mant_work + {{M{1'b0}},1'b1};
          carry_round  = mant_plus1[M];     // carry en el bit oculto
          mant_work    = mant_plus1;

          if (carry_round) begin
            // 1.xxx -> desplazar der 1 y exp+1
            mant_work = {1'b1, mant_work[M:1]};
            exp_work  = exp_work + 1;
          end
          inx = 1'b1;
        end else begin
          inx = (grs[2] | grs[1] | grs[0]);
        end

        // ---------- Empaquetado y flags ----------
        if (exp_work[E]) begin
          y   = {res_sign, {E{1'b1}}, {M{1'b0}}}; // +/-Inf
          ovf = 1'b1;
          inx = 1'b1;
        end else if (exp_work=={(E+1){1'b0}} && mant_work[M-1:0]=={M{1'b0}}) begin
          y = {res_sign, {E{1'b0}}, {M{1'b0}}};   // cero
        end else if (exp_work=={(E+1){1'b0}} && mant_work[M-1:0]!={M{1'b0}}) begin
          y   = {res_sign, {E{1'b0}}, mant_work[M-1:0]}; // subnormal
          udf = 1'b1; inx = 1'b1;
        end else begin
          y = {res_sign, exp_work[E-1:0], mant_work[M-1:0]}; // normal
        end
      end
    end

    flags = {ovf, udf, dbz, inv, inx};
  end

endmodule