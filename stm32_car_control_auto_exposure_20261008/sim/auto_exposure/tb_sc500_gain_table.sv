`timescale 1ns/1ps
module tb_sc500_gain_table;
  reg clk=0, rstn=0;
  reg [6:0] idx=0;
  wire [15:0] code;
  always #5 clk=~clk;
  SC500GainTbl dut(.I_clk(clk),.I_rstn(rstn),.I(idx),.O(code));
  initial begin
    #12; rstn=1;
    @(negedge clk); idx=0;
    @(negedge clk); if(code !== 16'h0320) $fatal(1,"1x gain code");
    idx=64;
    @(negedge clk); if(code !== 16'h0f20) $fatal(1,"4x gain code: %h",code);
    idx=96;
    @(negedge clk); if(code !== 16'h1f20) $fatal(1,"8x gain code: %h",code);
    idx=127;
    @(negedge clk); if(code !== 16'h1f3f) $fatal(1,"15.75x gain code: %h",code);
    $display("GAIN_TABLE_OK"); $finish;
  end
endmodule
