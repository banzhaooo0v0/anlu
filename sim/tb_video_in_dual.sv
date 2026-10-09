`timescale 1ns/1ps
// Exercise the production TD FIFO RTL with unrelated camera/DDR clocks.
module tb_video_in_dual;
    reg cam_clk = 0, ddr_clk = 0, rst_n = 0;
    always #5 cam_clk = ~cam_clk;
    always #2 ddr_clk = ~ddr_clk;
    reg raw_fs = 0, proc_fs = 0, raw_valid = 0, proc_valid = 0;
    reg [127:0] raw_data = 0, proc_data = 0;
    reg ready = 0, read_busy = 0;
    reg rx_error = 0;
    wire busy, req, we;
    wire [1:0] rp;
    wire [24:0] addr;
    wire [127:0] data;
    integer frame = 0, raw_seen = 0, proc_seen = 0, cycles = 0;
    integer slot = 0;
    integer words = 115200; // 1024 * 600 * RGB888 / 128
    reg checking = 0;
    video_in_dual dut (
        .I_rst_n(rst_n), .I_camera_clk(cam_clk),
        .I_camera_frame_start(proc_fs), .I_camera_valid(proc_valid), .I_camera_data(proc_data),
        .I_original_frame_start(raw_fs), .I_original_valid(raw_valid), .I_original_data(raw_data),
        .I_mipi_rx_error(rx_error), .I_ddr_clk(ddr_clk), .I_display_pause(1'b0),
        .I_video_out_rd_busy(read_busy), .O_video_in_wr_busy(busy), .O_video_out_rp(rp),
        .O_ddr_user_wr_en(we), .O_ddr_user_addr(addr), .O_ddr_user_wr_data(data),
        .I_ddr_user_ready(ready), .O_ddr_user_req(req)
    );
    function [127:0] pattern(input integer f, input integer source, input integer n);
        pattern = {32'hcafe1234 ^ f, 32'h01234567 ^ source, 32'h89abcdef ^ n, 32'h55aa0000 + n};
    endfunction
    always @(negedge ddr_clk) begin
        cycles = cycles + 1;
        ready = rst_n && (cycles % 13 != 0) && (cycles % 13 != 1);
        // A display burst can acquire the bus only between write bursts.
        read_busy = !busy && (cycles % 997 < 24);
    end
    always @(posedge ddr_clk) begin
        if (rst_n && we) begin
            if (!checking || !busy || !req) $fatal(1, "unexpected write or missing request/busy");
            if (addr >= slot*7000000+3500000) begin
                if (addr !== slot*7000000+3500000+proc_seen*8 ||
                    data !== pattern(frame, 1, proc_seen))
                    $fatal(1, "processed f=%0d n=%0d addr=%0d data=%h", frame, proc_seen, addr, data);
                proc_seen = proc_seen + 1;
            end else begin
                if (addr !== slot*7000000+raw_seen*8 ||
                    data !== pattern(frame, 0, raw_seen))
                    $fatal(1, "original f=%0d n=%0d addr=%0d data=%h", frame, raw_seen, addr, data);
                raw_seen = raw_seen + 1;
            end
        end
    end
    task send_raw;
        integer n;
        begin
            for (n=0; n<words; n=n+1) begin
                @(negedge cam_clk); raw_valid=1; raw_data=pattern(frame,0,n);
                @(negedge cam_clk); raw_valid=0;
            end
        end
    endtask
    task send_proc;
        integer n;
        begin
            repeat (6) @(negedge cam_clk);
            for (n=0; n<words; n=n+1) begin
                @(negedge cam_clk); proc_valid=1; proc_data=pattern(frame,1,n);
                @(negedge cam_clk); proc_valid=0;
            end
        end
    endtask
    initial begin
        #1; rst_n=0;
        repeat (12) @(negedge cam_clk);
        rst_n=1;
        for (frame=0; frame<7; frame=frame+1) begin
            rx_error=(frame==5);
            slot=(frame<5) ? frame%4 : frame-5;
            raw_seen=0; proc_seen=0; checking=1;
            @(negedge cam_clk); raw_fs=1; proc_fs=1;
            @(negedge cam_clk); raw_fs=0; proc_fs=0;
            // The production integration must provide this early reset marker.
            repeat (32) @(negedge cam_clk);
            fork send_raw(); send_proc(); join
            wait(raw_seen==words && proc_seen==words);
            repeat (50) @(negedge cam_clk);
            if (busy) $fatal(1, "write burst did not drain");
            checking=0;
        end
        $display("PASS: dual FIFO RTL, 7 frames, 115200 words/source/frame, stalls, frame-slot wrap and error retry");
        $finish;
    end
    initial begin #20000000; $fatal(1, "timeout raw=%0d proc=%0d",raw_seen,proc_seen); end
endmodule
