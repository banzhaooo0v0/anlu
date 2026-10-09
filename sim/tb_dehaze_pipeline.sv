`timescale 1ns/1ps
`include "dehaze_count.vh"
module tb_dehaze_pipeline;
    reg clk=0, rst_n=0;
    always #5 clk=~clk;
    reg [99:0] sample=0;
    wire user_o, last_o, valid_o;
    wire [95:0] data_o;
    reg [99:0] inputs [0:`DEHAZE_CYCLES-1];
    reg [98:0] expected [0:`DEHAZE_CYCLES-1];
    integer n;
    dehaze_stream_96 #(.IMG_WIDTH(64),.IMG_HEIGHT(5)) dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_tvalid(sample[99]),.I_tuser(sample[98]),
        .I_tlast(sample[97]),.I_enable(sample[96]),.I_tdata(sample[95:0]),
        .O_tvalid(valid_o),.O_tuser(user_o),.O_tlast(last_o),.O_tdata(data_o)
    );
    initial begin
        $readmemh("dehaze_input.hex",inputs);
        $readmemh("dehaze_expected.hex",expected);
        repeat(4) @(negedge clk);
        rst_n=1;
        for(n=0;n<`DEHAZE_CYCLES;n=n+1) begin
            sample=inputs[n];
            @(posedge clk); #1;
            if ({valid_o,user_o,last_o} !== expected[n][98:96])
                $fatal(1,"markers cycle %0d",n);
            if (valid_o && data_o !== expected[n][95:0])
                $fatal(1,"pixel cycle %0d got=%h expected=%h",n,data_o,expected[n][95:0]);
            @(negedge clk);
        end
        $display("PASS: dehaze pipeline 480 groups, 6 frames, borders/bubbles/mode latch/saturation");
        $finish;
    end
endmodule
