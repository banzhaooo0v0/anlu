module tb_osd_question;
  reg [7:0] character = 8'h3f;
  reg [3:0] row = 0;
  wire [15:0] bits;
  integer lit = 0;
  integer i;
  osd_char_lib dut(.I_char(character), .I_row(row), .O_row_bits(bits));
  initial begin
    for(i=0;i<16;i=i+1) begin
      row=i; #1;
      if(bits !== 16'h0000) lit=lit+1;
    end
    if(lit<5) $fatal(1,"Question mark glyph missing or incomplete: lit rows=%0d",lit);
    character=8'h4c; row=4'd3; #1;
    if(bits===16'h0000) $fatal(1,"Existing L glyph missing");
    $display("PASS OSD QUESTION GLYPH");
    $finish;
  end
endmodule
