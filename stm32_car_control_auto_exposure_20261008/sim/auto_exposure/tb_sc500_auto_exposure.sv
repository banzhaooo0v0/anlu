`timescale 1ns/1ps
module tb_sc500_auto_exposure;
    reg raw_clk = 0, cfg_clk = 0, raw_rst_n = 0, cfg_rst = 1;
    always #5 raw_clk = ~raw_clk;
    always #20 cfg_clk = ~cfg_clk;
    reg frame_start = 0, frame_end = 0, raw_valid = 0;
    reg [39:0] raw_data = 0;
    reg cam_done = 0, ae_done = 0;
    wire ae_req;
    wire [15:0] ae, ag;
    integer requests = 0;
    sc500_auto_exposure dut (
        .I_raw_clk(raw_clk), .I_raw_rst_n(raw_rst_n),
        .I_raw_frame_start(frame_start), .I_raw_frame_end(frame_end),
        .I_raw_valid(raw_valid), .I_raw_data(raw_data),
        .I_cfg_clk(cfg_clk), .I_cfg_rst(cfg_rst),
        .I_cam_cfg_done(cam_done), .I_ae_cfg_done(ae_done),
        .O_ae_req(ae_req), .O_ae(ae), .O_ag(ag)
    );
    always @(posedge cfg_clk) if (ae_req) requests = requests + 1;
    task send_frame(input [9:0] pixel);
        integer k;
        begin
            @(negedge raw_clk); frame_start = 1;
            @(negedge raw_clk); frame_start = 0; raw_valid = 1;
            raw_data = {20'd0, pixel, 10'd0};
            for (k = 0; k < 8192; k = k + 1) @(negedge raw_clk);
            raw_valid = 0; frame_end = 1;
            @(negedge raw_clk); frame_end = 0;
            repeat (20) @(negedge raw_clk);
        end
    endtask
    integer n;
    integer ag_before_bright;
    initial begin
        repeat (10) @(negedge cfg_clk);
        raw_rst_n = 1; cfg_rst = 0;
        cam_done = 1; ae_done = 1;
        if (ae != 1990 || ag != 80) $fatal(1,"reset mismatch");
        // The configured exposure is already at its VTS bound. Dark frames
        // must raise analogue gain, not exceed the exposure limit.
        for (n = 0; n < 10; n = n + 1) send_frame(10'd100);
        repeat (10) @(negedge cfg_clk);
        if (ae != 1990 || ag <= 80 || requests < 1)
            $fatal(1,"dark feedback failed: ae=%0d ag=%0d req=%0d",ae,ag,requests);
        $display("DARK_OK ae=%0d ag=%0d req=%0d",ae,ag,requests);
        ag_before_bright = ag;
        // Clipped frames must first reduce gain.
        for (n = 0; n < 10; n = n + 1) send_frame(10'd1000);
        repeat (10) @(negedge cfg_clk);
        if (ag >= ag_before_bright)
            $fatal(1,"bright feedback did not reduce gain: %0d",ag);
        if (ae > 1990 || ae < 6 || ag < 16 || ag > 143)
            $fatal(1,"control outside sensor bounds");
        $display("BRIGHT_OK ae=%0d ag=%0d req=%0d",ae,ag,requests);
        $finish;
    end
endmodule
