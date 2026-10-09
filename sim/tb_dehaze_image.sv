`timescale 1ns/1ps
`include "image_size.vh"
module tb_dehaze_image;
    localparam W=`IMAGE_WIDTH, H=`IMAGE_HEIGHT, GROUPS=W/4, N=GROUPS*H;
    reg clk=0, rst_n=0, valid_i=0, user_i=0, last_i=0;
    reg [95:0] data_i=0;
    always #5 clk=~clk;
    wire valid_o, user_o, last_o, bypass_valid, bypass_user, bypass_last;
    wire [95:0] data_o, bypass_data;
    reg [95:0] inputs [0:N-1];
    reg [10:0] valid_history=0, user_history=0, last_history=0;
    integer received=0, f_processed, f_original, y, x, k;
    dehaze_stream_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) processed (
        .I_clk(clk),.I_rst_n(rst_n),.I_tvalid(valid_i),.I_tuser(user_i),
        .I_tlast(last_i),.I_tdata(data_i),.I_enable(1'b1),
        .O_tvalid(valid_o),.O_tuser(user_o),.O_tlast(last_o),.O_tdata(data_o));
    dehaze_stream_96 #(.IMG_WIDTH(W),.IMG_HEIGHT(H)) original (
        .I_clk(clk),.I_rst_n(rst_n),.I_tvalid(valid_i),.I_tuser(user_i),
        .I_tlast(last_i),.I_tdata(data_i),.I_enable(1'b0),
        .O_tvalid(bypass_valid),.O_tuser(bypass_user),
        .O_tlast(bypass_last),.O_tdata(bypass_data));

    always @(posedge clk) begin
        if (rst_n) begin
            valid_history={valid_history[9:0],valid_i};
            user_history={user_history[9:0],valid_i && user_i};
            last_history={last_history[9:0],valid_i && last_i};
            #1;
            if ({valid_o,user_o,last_o} !==
                {valid_history[10],user_history[10],last_history[10]})
                $fatal(1,"Pipeline latency/marker mismatch at group %0d",received);
            if ({bypass_valid,bypass_user,bypass_last} !== {valid_o,user_o,last_o})
                $fatal(1,"Bypass marker mismatch");
            if (valid_o) begin
                if (received>=N) $fatal(1,"Extra output group");
                if (bypass_data !== inputs[received])
                    $fatal(1,"Original mismatch at group %0d",received);
                if ((^data_o) === 1'bx) $fatal(1,"Unknown processed pixel");
                $fdisplay(f_processed,"%024h",data_o);
                $fdisplay(f_original,"%024h",bypass_data);
                received=received+1;
            end
        end
    end
    initial begin
        $readmemh("image_input.hex",inputs);
        f_processed=$fopen("image_processed.hex","w");
        f_original=$fopen("image_original.hex","w");
        if (!f_processed || !f_original) $fatal(1,"Cannot open output files");
        repeat(4) @(negedge clk);
        rst_n=1;
        for(y=0;y<H;y=y+1) begin
            for(x=0;x<GROUPS;x=x+1) begin
                valid_i=1; user_i=(y==0 && x==0); last_i=(x==GROUPS-1);
                data_i=inputs[y*GROUPS+x];
                @(negedge clk);
            end
            valid_i=0; user_i=0; last_i=0;
            repeat(8) @(negedge clk);
        end
        repeat(20) @(negedge clk);
        if (received!=N) $fatal(1,"Output count %0d expected %0d",received,N);
        $fclose(f_processed); $fclose(f_original);
        $display("PASS: image RTL %0dx%0d, %0d groups, original exact, markers and latency checked",W,H,N);
        $finish;
    end
    initial begin
        #(20*(N+H*8+100));
        $fatal(1,"Timeout");
    end
endmodule
