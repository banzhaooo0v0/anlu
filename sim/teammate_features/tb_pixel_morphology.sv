`timescale 1ns/1ps
`include "morph_size.vh"
module tb_pixel_morphology;
    reg clk=0, rst_n=0;
    always #4.444 clk=~clk;
    reg [111:0] sample=0;
    reg [111:0] stimulus[0:`MORPH_N-1];
    reg [132:0] expected[0:`MORPH_N-1];
    wire valid_o,user_o,last_o,gv,gu,gl;
    wire [95:0] data_o;
    wire [31:0] gray;
    wire [1:0] mode_o;
    integer n, count=0;
    image_process_stream_96 #(.IMG_WIDTH(`MORPH_W),.IMG_HEIGHT(`MORPH_H)) dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_tvalid(sample[111]),.I_tuser(sample[110]),
        .I_tlast(sample[109]),.I_edge_threshold(sample[108:98]),
        .I_algo_mode(sample[97:96]),.I_tdata(sample[95:0]),
        .O_tvalid(valid_o),.O_tuser(user_o),.O_tlast(last_o),.O_tdata(data_o),
        .O_gray_tvalid(gv),.O_gray_tuser(gu),.O_gray_tlast(gl),.O_gray_data(gray),.O_gray_mode(mode_o));
    initial begin
        $readmemh("morph_input.hex",stimulus);
        $readmemh("morph_expected.hex",expected);
        repeat(4) @(negedge clk); rst_n=1;
        for(n=0;n<`MORPH_N;n=n+1) begin
            sample=stimulus[n]; @(posedge clk); #1;
            if ({valid_o,user_o,last_o} !== expected[n][132:130] ||
                {gv,gu,gl} !== expected[n][132:130]) $fatal(1,"morph markers cycle %0d",n);
            if(valid_o) begin
                if({mode_o,gray,data_o} !== expected[n][129:0])
                    $fatal(1,"morph pixels cycle %0d got=%h expected=%h",n,{mode_o,gray,data_o},expected[n][129:0]);
                count=count+1;
            end
            @(negedge clk);
        end
        if(count != 8*`MORPH_W*`MORPH_H/4) $fatal(1,"missing pixels");
        $display("PASS pixel morphology: %0d pixels, 8 frames, borders/bubbles/frame config/lane boundaries",count*4);
        $finish;
    end
endmodule
