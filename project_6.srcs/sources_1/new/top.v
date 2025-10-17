`timescale 1ns / 1ps
// Wrapper "top" para exponer interfaz simple de pruebas:
// a, b, ALUControl -> Result, ALUFlags
// Internamente instancia fp_alu (1 ciclo con start/valid_out)

module top (
    input  wire [31:0] a,
    input  wire [31:0] b,
    input  wire [3:0]  ALUControl,
    output wire [31:0] Result,
    output wire [4:0]  ALUFlags
);

  // ---------------- Reloj/reset internos (solo simulación) ----------------
  reg clk = 1'b0;
  reg rst = 1'b1;
  always #5 clk = ~clk;           // 100 MHz
  initial begin
    #20 rst = 1'b0;               // suelta reset tras 20 ns
  end

  // ---------------- Decodificación simple de ALUControl -------------------
  // Single: 1000=add, 1001=sub, 1010=mul, 1011=div
  // Half  : 1101=add, 1110=sub, 1100=mul, 1111=div (usa a[15:0], b[15:0])
  reg        mode_fp;      // 1=single, 0=half
  reg  [2:0] op_code;      // 000 add, 001 sub, 010 mul, 011 div
  always @* begin
    mode_fp = 1'b1;        // default: single
    op_code = 3'b000;      // default: add
    case (ALUControl)
      4'b1000: begin mode_fp=1'b1; op_code=3'b000; end // FADD single
      4'b1001: begin mode_fp=1'b1; op_code=3'b001; end // FSUB single
      4'b1010: begin mode_fp=1'b1; op_code=3'b010; end // FMUL single
      4'b1011: begin mode_fp=1'b1; op_code=3'b011; end // FDIV single
      4'b1101: begin mode_fp=1'b0; op_code=3'b000; end // FADD half
      4'b1110: begin mode_fp=1'b0; op_code=3'b001; end // FSUB half
      4'b1100: begin mode_fp=1'b0; op_code=3'b010; end // FMUL half
      4'b1111: begin mode_fp=1'b0; op_code=3'b011; end // FDIV half
      default: begin mode_fp=1'b1; op_code=3'b000; end
    endcase
  end

  // ---------------- Selección de operandos según formato ------------------
  wire [31:0] op_a_sel = mode_fp ? a : {16'b0, a[15:0]};
  wire [31:0] op_b_sel = mode_fp ? b : {16'b0, b[15:0]};

  // ---------------- Arranque automático al cambiar entradas ----------------
  // Genera un pulso de 'start' de 1 ciclo cuando cambian a/b/ALUControl
  reg  [31:0] a_d, b_d;
  reg  [3:0]  c_d;
  reg         start;
  always @(posedge clk or posedge rst) begin
    if (rst) begin
      a_d   <= 32'h0;
      b_d   <= 32'h0;
      c_d   <= 4'h0;
      start <= 1'b0;
    end else begin 
      // un ciclo de start si hay cambio
      start <= ((a!=a_d) || (b!=b_d) || (ALUControl!=c_d));
      a_d   <= a;
      b_d   <= b;
      c_d   <= ALUControl;
    end
  end

  // ---------------- Instancia de tu fp_alu ----------------
  wire [31:0] y_w;
  wire        valid_w;
  wire [4:0]  flags_w;

  fp_alu dut (
    .clk       (clk),
    .rst       (rst),
    .start     (start),
    .mode_fp   (mode_fp),
    .round_mode(2'b00),     // RNE
    .op_a      (op_a_sel),
    .op_b      (op_b_sel),
    .op_code   (op_code),
    .result    (y_w),
    .valid_out (valid_w),
    .flags     (flags_w)
  );

  // Exposición directa (el test espera con #delays)
  assign Result   = y_w;
  assign ALUFlags = flags_w;

endmodule