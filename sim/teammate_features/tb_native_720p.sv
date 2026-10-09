`timescale 1ns/1ps
module tb_native_720p;
  reg clk=0,rst=0,valid=0,fs=0,fe=0;
  reg [39:0] data=0;
  always #5 clk=~clk;
  wire ov,ou,ol; wire [39:0] od;
  integer f,y,x,count=0,starts=0,lines=0;
  uial2axis #(.IMG_WIDTH(1280),.IMG_HEIGHT(720),.INPUT_DATA_WIDTH(40)) dut
    (clk,rst,data,valid,fs,fe,ov,od,ou,ol);
  task send_frame;
    begin
      fs=1;@(negedge clk);fs=0;
      repeat(4) @(negedge clk);
      for(y=0;y<720;y=y+1) begin
        for(x=0;x<320;x=x+1) begin
          valid=1;data=f*10000000+y*1000+x;
          #1;
          if(!ov || od!==data || ou!==(x==0 && y==0) || ol!==(x==319))
            $fatal(1,"native marker/data f=%0d y=%0d x=%0d",f,y,x);
          count=count+1;starts=starts+ou;lines=lines+ol;
          @(negedge clk);
        end
        valid=0;fe=1;@(negedge clk);fe=0;repeat(3) @(negedge clk);
      end
    end
  endtask
  initial begin
    repeat(5) @(negedge clk);rst=1;
    for(f=0;f<2;f=f+1) send_frame;
    if(count!=460800 || starts!=2 || lines!=1440) $fatal(1,"native counts");
    $display("PASS native 720p: 2 frames, 1440 lines, 460800 four-pixel groups, end-marker gaps");
    $finish;
  end
endmodule
