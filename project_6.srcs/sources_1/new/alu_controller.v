`timescale 1ns / 1ps
// op_code decoder: 000=ADD, 001=SUB, 010=MUL, 011=DIV; otros = NOP
module alu_controller (
  input  wire [2:0] op_code,
  output wire do_add,
  output wire do_sub,
  output wire do_mul,
  output wire do_div
);
  assign do_add = (op_code == 3'b000);
  assign do_sub = (op_code == 3'b001);
  assign do_mul = (op_code == 3'b010);
  assign do_div = (op_code == 3'b011);
endmodule