`timescale 1ns/1ps
module tb_hdmi_black_camera;
reg clk=0, rst_n=0;
always #5 clk=~clk;
wire vs,hs,de,user,last,rd,ovs,ohs,ode;
wire [23:0] rgb;
uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),
        .V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) vtc(
 .I_vtc_rstn(rst_n),.I_vtc_clk(clk),.O_vtc_vs(vs),.O_vtc_hs(hs),.O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.IMG_WIDTH(1280),.IMG_HEIGHT(720)) mixer(
 .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),
 .I_debug_status(4'b0),.I_image_mode(2'b11),.I_traffic_sign_mode(1'b0),.I_traffic_sign_busy(1'b0),.I_traffic_sign_result_toggle(1'b0),.I_traffic_sign_result_ascii(8'h3f),
 .O_video_rd_en(rd),.I_video_rd_data(24'h000000),.O_hdmi_vsync(ovs),.O_hdmi_hsync(ohs),.O_hdmi_de(ode),.O_hdmi_data(rgb));
integer cycles=0,pixels=0,lines=0,line_pixels=0,reads=0,frames=0;
reg counting=0;
integer output_pixels=0, nonblack_pixels=0;
always @(negedge clk) if(rst_n) begin
 if (rd !== de) $fatal(1,"DDR read-enable mismatch");
 if(user && de) begin
  if(counting) begin
   if(cycles!=1650*750 || pixels!=1280*720 || lines!=720 || reads!=1280*720 || line_pixels!=0)
    $fatal(1,"HDMI counts cycles=%0d pixels=%0d lines=%0d reads=%0d",cycles,pixels,lines,reads);
   if(output_pixels!=1280*720 || nonblack_pixels==0)
    $fatal(1,"Black-camera OSD disappeared: output_pixels=%0d nonblack=%0d",output_pixels,nonblack_pixels);
   $display("Black-camera output pixels=%0d nonblack OSD pixels=%0d",output_pixels,nonblack_pixels);
   frames=frames+1;
   if(frames==2) begin
    $display("PASS HDMI BLACK CAMERA: mixer outputs full 720P frames with nonblack OSD even when camera input is zero");
    $finish;
   end
  end
  counting=1; cycles=0;pixels=0;lines=0;line_pixels=0;reads=0;output_pixels=0;nonblack_pixels=0;
 end
 if(counting) begin
  cycles=cycles+1;
  if(ode) begin output_pixels=output_pixels+1; if(rgb!==24'h000000 && !$isunknown(rgb)) nonblack_pixels=nonblack_pixels+1; end
  if(rd) reads=reads+1;
  if(de) begin
   pixels=pixels+1;line_pixels=line_pixels+1;
   if(last) begin
    if(line_pixels!=1280) $fatal(1,"HDMI line width=%0d",line_pixels);
    lines=lines+1;line_pixels=0;
   end
  end
 end
end
initial begin repeat(5) @(negedge clk); rst_n=1; end
initial begin #50000000; $fatal(1,"HDMI simulation timeout");end
endmodule
