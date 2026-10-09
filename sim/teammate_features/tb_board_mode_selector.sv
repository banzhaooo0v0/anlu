`timescale 1ns/1ps
module tb_board_mode_selector;
  reg clk=0, rst_n=0, key_n=1;
  reg [1:0] ext=2'b11;
  wire [1:0] mode;
  always #5 clk=~clk;
  mode_selector #(.DEBOUNCE_CYCLES(4),.SHORT_PRESS_LIMIT(30)) dut (
    .I_clk(clk),.I_rst_n(rst_n),.I_button(ext),
    .I_cycle_button_n(key_n),.O_mode(mode));

  task check(input [1:0] expected);
    begin
      repeat(4) @(posedge clk);
      if(mode !== expected) $fatal(1,"mode=%b expected=%b",mode,expected);
    end
  endtask
  task tap;
    begin
      key_n=0; repeat(12) @(posedge clk);
      key_n=1; repeat(12) @(posedge clk);
    end
  endtask
  initial begin
    repeat(4) @(posedge clk); rst_n=1;
    check(2'b11);
    tap(); check(2'b10);
    tap(); check(2'b01);
    tap(); check(2'b00);
    tap(); check(2'b11);
    key_n=0; repeat(55) @(posedge clk);
    key_n=1; repeat(12) @(posedge clk);
    check(2'b11); // long hold must not switch the image
    ext=2'b01; repeat(12) @(posedge clk); check(2'b01);
    ext=2'b11; repeat(12) @(posedge clk); check(2'b11);
    $display("PASS BOARD KEY4 MODE SELECTOR");
    $finish;
  end
endmodule
