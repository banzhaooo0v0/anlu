`timescale 1ns/1ps
// Production dehaze -> image processor -> two packers -> vendor FIFOs -> DDR.
// 60 MHz camera byte clock and 66.667 MHz DDR user clock from TD SDC.
// Camera blanking is synthetic; this does not model the sensor or DDR PHY.
module tb_member2_integration;
    reg cam=0,ddr=0,rst_n=0,early_fs=0;
    always #8.333 cam=~cam;
    always #7.5 ddr=~ddr;
    reg valid=0,user_i=0,last_i=0;
    reg [1:0] mode=0;
    wire dv,du,dl,pv,pu,pl;
    wire [95:0] dd,pd;
    wire rv128,pv128;
    wire [127:0] rd128,pd128;
    wire we,busy,req;
    wire [24:0] addr;
    wire [127:0] data;
    reg ready=0,read_busy=0;
    integer frame=0,y,x,raw_seen=0,proc_seen=0,cycles=0;
    dehaze_stream_96 haze (
        .I_clk(cam),.I_rst_n(rst_n),.I_tvalid(valid),.I_tuser(user_i),.I_tlast(last_i),
        .I_tdata({12{8'd200}}),.I_enable(mode==0),.O_tvalid(dv),.O_tuser(du),.O_tlast(dl),.O_tdata(dd));
    image_process_stream_96 process_image (
        .I_clk(cam),.I_rst_n(rst_n),.I_tvalid(dv),.I_tuser(du),.I_tlast(dl),.I_tdata(dd),
        .I_algo_mode(mode),.I_edge_threshold(11'd24),.O_tvalid(pv),.O_tuser(pu),.O_tlast(pl),.O_tdata(pd));
    data_96bit_to_128bit pack_raw (
        .I_clk(cam),.I_rst_n(rst_n),.I_96b_frame_start(user_i),.I_96b_last(last_i),
        .I_96b_valid(valid),.I_96b_data({12{8'd200}}),.O_128b_valid(rv128),.O_128b_data(rd128));
    data_96bit_to_128bit pack_proc (
        .I_clk(cam),.I_rst_n(rst_n),.I_96b_frame_start(pu),.I_96b_last(pl),
        .I_96b_valid(pv),.I_96b_data(pd),.O_128b_valid(pv128),.O_128b_data(pd128));
    video_in_dual writer (
        .I_rst_n(rst_n),.I_camera_clk(cam),.I_camera_frame_start(early_fs),
        .I_original_frame_start(early_fs),.I_camera_valid(pv128),.I_camera_data(pd128),
        .I_original_valid(rv128),.I_original_data(rd128),.I_mipi_rx_error(1'b0),
        .I_ddr_clk(ddr),.I_display_pause(1'b0),.I_video_out_rd_busy(read_busy),
        .O_video_in_wr_busy(busy),.O_video_out_rp(),.O_ddr_user_wr_en(we),
        .O_ddr_user_addr(addr),.O_ddr_user_wr_data(data),.I_ddr_user_ready(ready),.O_ddr_user_req(req));
    always @(negedge ddr) begin
        cycles=cycles+1;
        ready=rst_n && (cycles%17 != 0);
        read_busy=!busy && cycles%997<120;
    end
    always @(posedge ddr) if (rst_n && we) begin
        if (!busy || !req) $fatal(1,"DDR ownership");
        if (addr >= frame*7000000+3500000) begin
            if (addr !== frame*7000000+3500000+proc_seen*8 ||
                data !== (frame==0 ? {16{8'd160}} : {16{8'd200}}))
                $fatal(1,"integrated processed frame=%0d beat=%0d addr=%0d data=%h",frame,proc_seen,addr,data);
            proc_seen=proc_seen+1;
        end else begin
            if (addr !== frame*7000000+raw_seen*8 || data !== {16{8'd200}})
                $fatal(1,"integrated raw frame=%0d beat=%0d addr=%0d data=%h",frame,raw_seen,addr,data);
            raw_seen=raw_seen+1;
        end
    end
    initial begin
        repeat(12) @(negedge cam); rst_n=1;
        for(frame=0;frame<2;frame=frame+1) begin
            mode=frame==0 ? 0 : 3;
            raw_seen=0;proc_seen=0;
            early_fs=1; @(negedge cam); early_fs=0;
            repeat(64) @(negedge cam);
            for(y=0;y<720;y=y+1) begin
                for(x=0;x<320;x=x+1) begin
                    valid=1;user_i=(x==0 && y==0);last_i=(x==319);
                    @(negedge cam);
                end
                valid=0;user_i=0;last_i=0;
                repeat(1024) @(negedge cam);
            end
            wait(raw_seen==172800 && proc_seen==172800);
            repeat(100) @(negedge cam);
        end
        $display("PASS: integrated member2 path, two 1280x720 frames, 691200 DDR words, dehaze/bypass and actual clock ratio");
        $finish;
    end
    initial begin #50000000; $fatal(1,"integration timeout raw=%0d proc=%0d",raw_seen,proc_seen); end
endmodule
