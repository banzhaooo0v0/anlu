`timescale 1ns/1ps
module tb_hdmi_720p;
reg clk=0, rst_n=0, result_toggle=0;
always #5 clk=~clk;
wire vs,hs,de,user,last,rd,ovs,ohs,ode;
wire [23:0] rgb;
uivtc #(.H_ActiveSize(1280),.H_FrameSize(1650),.H_SyncStart(1390),.H_SyncEnd(1430),
        .V_ActiveSize(720),.V_FrameSize(750),.V_SyncStart(725),.V_SyncEnd(730)) vtc(
 .I_vtc_rstn(rst_n),.I_vtc_clk(clk),.O_vtc_vs(vs),.O_vtc_hs(hs),.O_vtc_de_valid(de),.O_vtc_user(user),.O_vtc_last(last));
hdmi_mixer #(.H_OFFSET(0),.V_OFFSET(0),.IMG_WIDTH(1280),.IMG_HEIGHT(720)) mixer(
 .I_clk(clk),.I_rst_n(rst_n),.I_video_vsync(vs),.I_video_hsync(hs),.I_video_de(de),.I_video_user(user),.I_video_last(last),
 .I_debug_status(4'b0),.I_image_mode(2'b00),.I_cnn_mode(1'b1),.I_cnn_busy(1'b0),.I_cnn_result_toggle(result_toggle),.I_cnn_result_ascii(8'h41),
 .I_sign_toggle(result_toggle),.I_sign_ascii(8'h3f),
 .O_video_rd_en(rd),.I_video_rd_data(24'h123456),.O_hdmi_vsync(ovs),.O_hdmi_hsync(ohs),.O_hdmi_de(ode),.O_hdmi_data(rgb));
// End-to-end pixel scoreboard for all three new/existing text rows.
reg [11:0] text_x0,text_x1,text_y0,text_y1;
reg text_de0,text_de1;
reg [7:0] ref_char;
reg [3:0] ref_row,ref_col;
wire [15:0] ref_bits;
reg [63:0] expected_text;
integer text_checks=0;
reg saw_frame_start=0;
always @(posedge clk) if(user) saw_frame_start<=1;
osd_char_lib reference_font(ref_char,ref_row,ref_bits);
always @(posedge clk) begin
 text_x0<=mixer.S_x_2d;text_x1<=text_x0;
 text_y0<=mixer.S_y_2d;text_y1<=text_y0;
 text_de0<=mixer.S_video_de_2d;text_de1<=text_de0;
end
always @(negedge clk) if(rst_n && saw_frame_start && text_de1 && text_x1>=375 && text_x1<503) begin
 expected_text=0;
 if(text_y1>=154 && text_y1<170) begin expected_text="CNN:A   ";ref_row=text_y1-154;end
 if(text_y1>=184 && text_y1<200) begin expected_text="MODE:HAZ";ref_row=text_y1-184;end
 if(text_y1>=214 && text_y1<230) begin expected_text="DIR:?   ";ref_row=text_y1-214;end
 if(expected_text!=0) begin
  ref_char=expected_text >> (56-8*((text_x1-375)/16));
  ref_col=(text_x1-375)%16;
  #1;
  if(rgb !== (ref_bits[15-ref_col] ? 24'hfff200 : 24'h123456))
   $fatal(1,"OSD pixel x=%0d y=%0d char=%h rgb=%h",text_x1,text_y1,ref_char,rgb);
  text_checks=text_checks+1;
 end
end
integer cycles=0,pixels=0,lines=0,line_pixels=0,reads=0,frames=0,mode_pixels=0,question_pixels=0;
reg counting=0;
always @(negedge clk) if(rst_n) begin
 if (rd !== de) $fatal(1,"DDR read-enable mismatch");
 if(user && de) begin
  if(counting) begin
   if(cycles!=1650*750 || pixels!=1280*720 || lines!=720 || reads!=1280*720 || line_pixels!=0)
    $fatal(1,"HDMI counts cycles=%0d pixels=%0d lines=%0d reads=%0d",cycles,pixels,lines,reads);
   if(mode_pixels==0) $fatal(1,"MODE:HAZ OSD produced no pixels");
   if(question_pixels==0) $fatal(1,"DIR:? question mark produced no pixels");
   frames=frames+1;
   if(frames==2) begin
    if(text_checks<12000) $fatal(1,"missing OSD pixel checks");
    $display("PASS OSD final output pixels: %0d",text_checks);
    $display("PASS HDMI 1280x720: 921600 pixels, 720 lines, 1237500 clocks/frame; two frames checked");
    $finish;
   end
  end
  counting=1; cycles=0;pixels=0;lines=0;line_pixels=0;reads=0;mode_pixels=0;question_pixels=0;
 end
 if(counting) begin
  if(mixer.S_x_2d>=375 && mixer.S_x_2d<503 &&
     mixer.S_y_2d>=180 && mixer.S_y_2d<204 && mixer.glyph_region_q && (mixer.S_pf_row_bits != 0))
   mode_pixels=mode_pixels+1;
  if(mixer.S_x_2d>=439 && mixer.S_x_2d<455 &&
     mixer.S_y_2d>=210 && mixer.S_y_2d<234 && mixer.glyph_region_q && (mixer.S_pf_row_bits != 0))
   question_pixels=question_pixels+1;
  cycles=cycles+1;
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
initial begin repeat(5) @(negedge clk); rst_n=1; repeat(4) @(negedge clk); result_toggle=1; end
initial begin #50000000; $fatal(1,"HDMI simulation timeout");end
endmodule
