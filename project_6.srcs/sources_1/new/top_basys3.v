`timescale 1ns / 1ps
// Demo HW wrapper para Basys3 (IEEE-754 half, 16-bit)
// - SW[15:0] : datos de entrada para cargar A o B
// - BTN_U    : load A  (captura SW en A)
// - BTN_R    : load B  (captura SW en B)
// - BTN_D    : next op (ADD -> SUB -> MUL -> DIV -> ...)
// - BTN_L    : toggle vista (0=Result[15:0] en LEDs, 1=Flags en LEDs[4:0])
// - BTN_C    : reset
// - LEDS     : resultado o flags (según vista)
//
// Requiere: fp_alu.v, fp_addsub.v, fp_mul.v, fp_div.v, alu_controller.v

module top_basys3 (
  input  wire        CLK100MHZ,
  input  wire [15:0] sw,
  input  wire        btnC, btnU, btnR, btnD, btnL,
  output reg  [15:0] led
);
  //------------------------------------------------------------------
  // Sincronización de botones y detección de flancos (1 ciclo)
  //------------------------------------------------------------------
  reg [4:0] btn_d1, btn_d2;
  wire pC, pU, pR, pD, pL;

  always @(posedge CLK100MHZ) begin
    btn_d1 <= {btnC, btnU, btnR, btnD, btnL};
    btn_d2 <= btn_d1;
  end
  assign pC = (btn_d1[4] & ~btn_d2[4]); // center
  assign pU = (btn_d1[3] & ~btn_d2[3]); // up
  assign pR = (btn_d1[2] & ~btn_d2[2]); // right
  assign pD = (btn_d1[1] & ~btn_d2[1]); // down
  assign pL = (btn_d1[0] & ~btn_d2[0]); // left

  //------------------------------------------------------------------
  // Registros de A, B (half) y selección de operación
  //------------------------------------------------------------------
  reg        rst;
  reg [15:0] a16, b16;
  reg [1:0]  op_sel;  // 0=ADD,1=SUB,2=MUL,3=DIV
  reg        view_flags; // 0: result, 1: flags
  reg        start;      // pulso 1 ciclo

  always @(posedge CLK100MHZ) begin
    // reset síncrono con BTN_C
    if (pC) begin
      a16 <= 16'h0000;
      b16 <= 16'h0000;
      op_sel <= 2'd0;
      view_flags <= 1'b0;
      start <= 1'b0;
      rst <= 1'b1;
    end else begin
      rst <= 1'b0;

      // capturas y cambio de operación -> generan 'start'
      start <= 1'b0;
      if (pU) begin
        a16  <= sw;
        start <= 1'b1;
      end
      if (pR) begin
        b16  <= sw;
        start <= 1'b1;
      end
      if (pD) begin
        op_sel <= op_sel + 2'd1;
        start  <= 1'b1;
      end
      if (pL) begin
        view_flags <= ~view_flags;
      end
    end
  end

  // Mapeo a op_code del core
  wire [2:0] op_code = (op_sel==2'd0) ? 3'b000 : // ADD
                       (op_sel==2'd1) ? 3'b001 : // SUB
                       (op_sel==2'd2) ? 3'b010 : // MUL
                                        3'b011 ; // DIV

  // Operandos a 32 bits (half en [15:0])
  wire [31:0] op_a = {16'h0000, a16};
  wire [31:0] op_b = {16'h0000, b16};

  //------------------------------------------------------------------
  // Instancia del core: modo half, RNE, 1 ciclo
  //------------------------------------------------------------------
  wire [31:0] y_w;
  wire [4:0]  flags_w;
  wire        valid_w;

  fp_alu dut (
    .clk        (CLK100MHZ),
    .rst        (rst),
    .start      (start),
    .mode_fp    (1'b0),     // half
    .round_mode (2'b00),    // RNE
    .op_a       (op_a),
    .op_b       (op_b),
    .op_code    (op_code),
    .result     (y_w),
    .valid_out  (valid_w),
    .flags      (flags_w)
  );

  //------------------------------------------------------------------
  // Salida a LEDs: resultado (16b) o flags (5b)
  //------------------------------------------------------------------
  always @(posedge CLK100MHZ) begin
    if (view_flags)
      led <= {11'b0, flags_w}; // LED[4:0]=flags
    else
      led <= y_w[15:0];        // resultado half
  end

endmodule
