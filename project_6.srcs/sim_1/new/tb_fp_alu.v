`timescale 1ns / 1ns
//////////////////////////////////////////////////////////////////////////////////
// TB "a,b,ALUControl" para top (wrapper de fp_alu)
// - Cubre SINGLE y HALF
// - Incluye casos límite (NaN, ±Inf, ±0, UDF, OVF, DBZ, INX) y checks básicos
// - Verilog-2001 puro (sin SV)
//
// Flags = {OVF, UDF, DBZ, INV, INX}
//////////////////////////////////////////////////////////////////////////////////

module tb;

  // Entradas al DUT
  reg [31:0] a, b;
  reg [3:0]  ALUControl;

  // Salidas del DUT
  wire [31:0] Result;
  wire [4:0]  ALUFlags;

  // Contadores de verificación
  integer pass_cnt = 0;
  integer fail_cnt = 0;

  // Instancia del wrapper
  top uut (
    .a(a),
    .b(b),
    .ALUControl(ALUControl),
    .Result(Result),
    .ALUFlags(ALUFlags)
  );

  // Constantes de control (mapeo del top)
  localparam [3:0] FADD32 = 4'b1000,
                   FSUB32 = 4'b1001,
                   FMUL32 = 4'b1010,
                   FDIV32 = 4'b1011,
                   FADD16 = 4'b1101,
                   FSUB16 = 4'b1110,
                   FMUL16 = 4'b1100,
                   FDIV16 = 4'b1111;

  // Helpers de impresión
  task show32(input [127:0] tag);
    begin
      $display("%s | A=0x%08h  B=0x%08h  -> Result=0x%08h  Flags=%05b",
               tag, a, b, Result, ALUFlags);
    end
  endtask

  task show16(input [127:0] tag);
    begin
      $display("%s | A=0x%04h  B=0x%04h  -> Result=0x%04h  Flags=%05b",
               tag, a[15:0], b[15:0], Result[15:0], ALUFlags);
    end
  endtask

  // Checkers compactos
  task chk32(input [31:0] exp_res, input [4:0] exp_flags, input [127:0] tag);
    begin
      show32(tag);
      if ((Result!==exp_res) || (ALUFlags!==exp_flags)) begin
        $display("  FAIL exp_res=0x%08h exp_flags=%05b", exp_res, exp_flags);
        fail_cnt = fail_cnt + 1;
      end else begin
        $display("  PASS");
        pass_cnt = pass_cnt + 1;
      end
    end
  endtask

  task chk16(input [15:0] exp_res16, input [4:0] exp_flags, input [127:0] tag);
    begin
      show16(tag);
      if ((Result[15:0]!==exp_res16) || (ALUFlags!==exp_flags)) begin
        $display("  FAIL exp_res16=0x%04h exp_flags=%05b", exp_res16, exp_flags);
        fail_cnt = fail_cnt + 1;
      end else begin
        $display("  PASS");
        pass_cnt = pass_cnt + 1;
      end
    end
  endtask

  // Test: conmutatividad puntual (no necesita expected absolutos)
  task chk_comm32(input [3:0] ctl, input [31:0] A, input [31:0] B, input [127:0] tag);
    reg [31:0] y1, y2; reg [4:0] f1, f2;
    begin
      ALUControl = ctl; a = A; b = B; #25; y1 = Result; f1 = ALUFlags;
      ALUControl = ctl; a = B; b = A; #25; y2 = Result; f2 = ALUFlags;
      $display("%s | y1=0x%08h f1=%05b  y2=0x%08h f2=%05b", tag, y1, f1, y2, f2);
      if ((y1!==y2) || (f1!==f2)) begin
        $display("  FAIL (no conmutativo)");
        fail_cnt = fail_cnt + 1;
      end else begin
        $display("  PASS");
        pass_cnt = pass_cnt + 1;
      end
    end
  endtask

  task chk_comm16(input [3:0] ctl, input [15:0] A16, input [15:0] B16, input [127:0] tag);
    reg [15:0] y1, y2; reg [4:0] f1, f2;
    begin
      ALUControl = ctl; a = {16'h0000, A16}; b = {16'h0000, B16}; #25; y1 = Result[15:0]; f1 = ALUFlags;
      ALUControl = ctl; a = {16'h0000, B16}; b = {16'h0000, A16}; #25; y2 = Result[15:0]; f2 = ALUFlags;
      $display("%s | y1=0x%04h f1=%05b  y2=0x%04h f2=%05b", tag, y1, f1, y2, f2);
      if ((y1!==y2) || (f1!==f2)) begin
        $display("  FAIL (no conmutativo)");
        fail_cnt = fail_cnt + 1;
      end else begin
        $display("  PASS");
        pass_cnt = pass_cnt + 1;
      end
    end
  endtask

  initial begin
    $display("=== INICIO TEST FP_ALU ===");

    // Inicial: evita pulso start en reset
    a = 32'h0000_0000;
    b = 32'h0000_0000;
    ALUControl = 4'h0;

    // Espera a que el 'top' suelte reset (lo hace en #20) y evita flanco de 30 ns
    #31;

    // =========================================================================
    // SINGLE (float32)
    // =========================================================================

    // Básicos correctos
    ALUControl=FADD32; a=32'h3FC0_0000; b=32'h4000_0000; #25; chk32(32'h4060_0000, 5'b00000, "FADD32 1.5+2.0");
    ALUControl=FSUB32; a=32'h4000_0000; b=32'h3F80_0000; #25; chk32(32'h3F80_0000, 5'b00000, "FSUB32 2.0-1.0");
    ALUControl=FMUL32; a=32'h3FC0_0000; b=32'h4000_0000; #25; chk32(32'h4040_0000, 5'b00000, "FMUL32 1.5*2.0");
    ALUControl=FDIV32; a=32'h3F80_0000; b=32'h4000_0000; #25; chk32(32'h3F00_0000, 5'b00000, "FDIV32 1.0/2.0");

    // Divide by zero
    ALUControl=FDIV32; a=32'h3F80_0000; b=32'h0000_0000; #25; chk32(32'h7F80_0000, 5'b00101, "FDIV32 1.0/0.0 -> +Inf (DBZ,INX)");

    // Inválido: 0 * +Inf -> qNaN
    ALUControl=FMUL32; a=32'h0000_0000; b=32'h7F80_0000; #25; chk32(32'h7FC0_0000, 5'b00010, "FMUL32 0 * +Inf -> NaN (INV)");

    // Overflow: max + max -> +Inf (OVF, INX)
    ALUControl=FADD32; a=32'h7F7F_FFFF; b=32'h7F7F_FFFF; #25; chk32(32'h7F80_0000, 5'b10001, "FADD32 max+max -> +Inf (OVF,INX)");

    // Underflow a subnormal: (min normal)/2 -> subnormal (UDF, INX)
    // min normal single = 0x00800000 ; 1/2 = 0x3F000000
    ALUControl=FDIV32; a=32'h0080_0000; b=32'h4000_0000; #25; chk32(32'h0040_0000, 5'b01001, "FDIV32 (minN)/2 -> subnormal (UDF,INX)");

    // +0 + (-0) -> -0 (según tu convención XOR)
    ALUControl=FADD32; a=32'h0000_0000; b=32'h8000_0000; #25; chk32(32'h8000_0000, 5'b00000, "FADD32 +0 + -0 -> -0");

    // +Inf - +Inf -> NaN (INV)
    ALUControl=FSUB32; a=32'h7F80_0000; b=32'h7F80_0000; #25; chk32(32'h7FC0_0000, 5'b00010, "FSUB32 +Inf - +Inf -> NaN (INV)");

    // Inexact típico: 1/3 (RNE)
    ALUControl=FDIV32; a=32'h3F80_0000; b=32'h4040_0000; #25; chk32(32'h3EAA_AAAB, 5'b00001, "FDIV32 1.0/3.0 -> 0x3EAAAAAB (INX)");

    // Conmutatividad puntual (suma y mul)
    chk_comm32(FADD32, 32'h4120_0000/*10.0*/, 32'hC100_0000/*-8.0*/, "COMM32 FADD");
    chk_comm32(FMUL32, 32'h40A0_0000/*5.0*/,  32'hBF80_0000/*-1.0*/, "COMM32 FMUL");

    // =========================================================================
    // HALF (float16)  -> usar Result[15:0]
    // =========================================================================

    // Básicos correctos
    ALUControl=FADD16; a=32'h0000_3C00; b=32'h0000_4000; #25; chk16(16'h4200, 5'b00000, "FADD16 1.0h+2.0h=3.0h");
    ALUControl=FSUB16; a=32'h0000_4000; b=32'h0000_3C00; #25; chk16(16'h3C00, 5'b00000, "FSUB16 2.0h-1.0h=1.0h");
    ALUControl=FMUL16; a=32'h0000_3E00; b=32'h0000_4000; #25; chk16(16'h4200, 5'b00000, "FMUL16 1.5h*2.0h=3.0h");
    ALUControl=FDIV16; a=32'h0000_3C00; b=32'h0000_4000; #25; chk16(16'h3800, 5'b00000, "FDIV16 1.0h/2.0h=0.5h");

    // Divide by zero
    ALUControl=FDIV16; a=32'h0000_3C00; b=32'h0000_0000; #25; chk16(16'h7C00, 5'b00101, "FDIV16 1.0h/0 -> +Infh (DBZ,INX)");

    // Inválido: 0 * +Infh
    ALUControl=FMUL16; a=32'h0000_0000; b=32'h0000_7C00; #25; chk16(16'h7E00, 5'b00010, "FMUL16 0 * +Infh -> NaNh (INV)");

    // Overflow en half: max+max -> +Infh (OVF, INX)
    // max half = 0x7BFF (~65504)
    ALUControl=FADD16; a=32'h0000_7BFF; b=32'h0000_7BFF; #25; chk16(16'h7C00, 5'b10001, "FADD16 max+max -> +Infh (OVF,INX)");

    // Underflow a subnormal en half: (min normal)/2 -> subnormal (UDF, INX)
    // min normal half = 0x0400 ; (1/2)=0x0200 (subnormal)
    ALUControl=FDIV16; a=32'h0000_0400; b=32'h0000_4000; #25; chk16(16'h0200, 5'b01001, "FDIV16 (minN)/2 -> subnormal (UDF,INX)");

    // +0h + -0h -> -0h
    ALUControl=FADD16; a=32'h0000_0000; b=32'h0000_8000; #25; chk16(16'h8000, 5'b00000, "FADD16 +0h + -0h -> -0h");

    // +Infh - +Infh -> NaNh (INV)
    ALUControl=FSUB16; a=32'h0000_7C00; b=32'h0000_7C00; #25; chk16(16'h7E00, 5'b00010, "FSUB16 +Infh - +Infh -> NaNh");

    // Inexact típico en half: 1/3
    // 1.0h = 0x3C00 ; 3.0h = 0x4200 ; 1/3 ≈ 0x3555 con RNE
    ALUControl=FDIV16; a=32'h0000_3C00; b=32'h0000_4200; #25; chk16(16'h3555, 5'b00001, "FDIV16 1.0h/3.0h -> 0x3555 (INX)");

    // Conmutatividad puntual
    chk_comm16(FADD16, 16'h3A00/*0.75h*/, 16'hC000/*-2.0h*/, "COMM16 FADD");
    chk_comm16(FMUL16, 16'h3C00/*1.0h*/,  16'hBC00/*-1.0h*/, "COMM16 FMUL");

    // =========================================================================
    // Resumen
    // =========================================================================
    $display("=== FIN TEST ===  PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
    if (fail_cnt==0) $display(">>> TODO OK segun checks.");
    else             $display(">>> Hay fallas. Revisar arriba.");

    $finish;
  end

endmodule
