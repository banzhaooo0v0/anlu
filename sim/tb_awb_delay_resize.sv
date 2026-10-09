`timescale 1ns/1ps
module awb_delay_case #(parameter WIDTH=1024)(output reg done=0);
    reg clk=0, rst_n=0, fs=0, valid=0;
    reg [95:0] data=0;
    always #5 clk=~clk;
    wire new_valid,old_valid,new_user,old_user;
    wire [95:0] new_data,old_data;
    integer f,y,x,seen=0;
    signal_delay #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(3)) dut (
        .I_clk(clk),.I_rst_n(rst_n),.I_tuser(fs),.I_valid(valid),.I_data(data),
        .O_valid(new_valid),.O_data(new_data),.O_tuser(new_user));
    signal_delay_baseline #(.IMG_WIDTH(WIDTH),.IMG_HEIGHT(3)) reference (
        .I_clk(clk),.I_rst_n(rst_n),.I_tuser(fs),.I_valid(valid),.I_data(data),
        .O_valid(old_valid),.O_data(old_data),.O_tuser(old_user));
    always @(posedge clk) begin
        #1;
        if (rst_n && !done) begin
            if ({new_valid,new_user} !== {old_valid,old_user}) $fatal(1,"AWB marker width=%0d",WIDTH);
            if (new_valid) begin
                if (new_data !== old_data || (^new_data) === 1'bx)
                    $fatal(1,"AWB RAM data width=%0d n=%0d",WIDTH,seen);
                seen=seen+1;
            end
        end
    end
    initial begin
        repeat(8) @(negedge clk);
        rst_n=1;
        for(f=0;f<2;f=f+1) begin
            fs=1; @(negedge clk); fs=0;
            repeat(12) @(negedge clk);
            for(y=0;y<3;y=y+1) begin
                for(x=0;x<WIDTH/4;x=x+1) begin
                    valid=1; data={32'h12340000+f,32'h56780000+y,32'h9abc0000+x};
                    @(negedge clk);
                end
                valid=0;
                repeat(100) @(negedge clk);
            end
        end
        if (seen != 2*3*WIDTH/4) $fatal(1,"AWB count %0d width=%0d",seen,WIDTH);
        $display("PASS: AWB RAM address/depth equivalence (behavioral model), width=%0d groups=%0d",WIDTH,seen);
        done=1;
    end
endmodule
module tb_awb_delay_resize;
    wire done1,done2,done3;
    awb_delay_case #(.WIDTH(1024)) a(done1);
    awb_delay_case #(.WIDTH(1920)) b(done2);
    awb_delay_case #(.WIDTH(1280)) c(done3);
    initial begin wait(done1 && done2 && done3); $finish; end
    initial begin #1000000; $fatal(1,"AWB timeout"); end
endmodule
