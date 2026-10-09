`timescale 1ns/1ps
// Compare production row controllers against the original 2048-word versions.
// Both use the explicit portable RAM contract, not encrypted vendor primitives.
module tb_demosaic_ram_resize;
    reg clk=0,rst_n=0,fs=0,valid=0,last=0;
    reg [32:0] data=0;
    wire nv,ov,nz,oz,nu,ou,nl,ol;
    wire [32:0] nd,od;
    wire [31:0] nzd,ozd;
    integer f,y,x,seen=0;
    always #5 clk=~clk;
    line_buffer_demosaic #(.IMG_WIDTH(1280),.IMG_HEIGHT(9)) dut_line (
      .I_clk(clk),.I_rst_n(rst_n),.I_tuser(fs),.I_valid(valid),.I_data(data),.O_valid(nv),.O_data(nd));
    line_buffer_demosaic_baseline #(.IMG_WIDTH(1280),.IMG_HEIGHT(9)) ref_line (
      .I_clk(clk),.I_rst_n(rst_n),.I_tuser(fs),.I_valid(valid),.I_data(data),.O_valid(ov),.O_data(od));
    zhenghe #(.IMG_WIDTH(1280),.IMG_HEIGHT(9),.DATA_WIDTH(32)) dut_align (
      .I_clk(clk),.I_rst_n(rst_n),.I_tuser(fs),.I_tvalid(valid),.I_tdata(data[31:0]),.I_tlast(last),
      .O_tvalid(nz),.O_tdata(nzd),.O_tuser(nu),.O_tlast(nl));
    zhenghe_baseline #(.IMG_WIDTH(1280),.IMG_HEIGHT(9),.DATA_WIDTH(32)) ref_align (
      .I_clk(clk),.I_rst_n(rst_n),.I_tuser(fs),.I_tvalid(valid),.I_tdata(data[31:0]),.I_tlast(last),
      .O_tvalid(oz),.O_tdata(ozd),.O_tuser(ou),.O_tlast(ol));
    always @(posedge clk) begin
      #1;
      if(rst_n) begin
        if({nv,nz,nu,nl} !== {ov,oz,ou,ol}) $fatal(1,"Demosaic marker mismatch");
        if(nv && nd !== od) $fatal(1,"Line data mismatch");
        if(nz && nzd !== ozd) $fatal(1,"Alignment data mismatch");
        if(nv || nz) seen=seen+1;
      end
    end
    task send_rows;
      begin
        fs=1; @(negedge clk); fs=0; repeat(10) @(negedge clk);
        for(y=0;y<9;y=y+1) begin
          for(x=0;x<320;x=x+1) begin
            valid=1;last=(x==319);data=33'h100000000+f*100000+y*1000+x;
            @(negedge clk);
            if(x%17==0) begin
              valid=0;last=0;data=33'h12345678;
              @(negedge clk);
            end
          end
          valid=0;last=0;repeat(150) @(negedge clk);
        end
        repeat(200) @(negedge clk);
      end
    endtask
    initial begin
      repeat(5) @(negedge clk);rst_n=1;
      for(f=0;f<3;f=f+1) send_rows;
      if(seen<8000) $fatal(1,"Insufficient checks %0d",seen);
      $display("PASS demosaic RAM depth/address equivalence: %0d valid cycles",seen);
      $finish;
    end
    initial begin #2000000;$fatal(1,"RAM timeout");end
endmodule
