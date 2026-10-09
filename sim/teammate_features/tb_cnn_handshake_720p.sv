`timescale 1ns/1ps

// 验证输入采样器的帧完成握手、双缓冲占用和整帧丢弃行为。
module tb_cnn_handshake_720p;

    localparam integer IMG_WIDTH  = 1280;
    localparam integer IMG_HEIGHT = 720;
    localparam integer CNN_SIZE   = 64;
    localparam integer GROUPS     = IMG_WIDTH / 4;

    reg clk;
    reg rst_n;
    reg tuser;
    reg tlast;
    reg tvalid;
    reg [31:0] gray_data;
    reg core_busy;
    reg core_done;
    reg core_bank;
    wire core_start;
    wire core_input_bank;
    wire core_frame_ready;
    reg core_rd_bank;
    reg [11:0] core_rd_addr;
    wire [7:0] core_rd_data;
    wire frame_drop;

    integer error_count;
    integer start_count;
    integer source_y;
    integer x_group;
    integer frame_id;
    integer wait_count;
    integer address;
    reg frame0_finished;
    reg frame1_finished;

    cnn_input_sampler_96 #(.IMG_WIDTH(1280),.IMG_HEIGHT(720)) dut (
        .I_clk                    (clk),
        .I_rst_n                   (rst_n),
        .I_tuser                   (tuser),
        .I_tlast                   (tlast),
        .I_tvalid                  (tvalid),
        .I_gray_data               (gray_data),
        .I_core_busy               (core_busy),
        .I_core_done               (core_done),
        .I_core_bank               (core_bank),
        .O_core_start              (core_start),
        .O_core_input_bank         (core_input_bank),
        .O_core_input_frame_ready  (core_frame_ready),
        .I_core_rd_bank            (core_rd_bank),
        .I_core_rd_addr            (core_rd_addr),
        .O_core_rd_data            (core_rd_data),
        .O_frame_drop              (frame_drop),
        .O_capture_active          ()
    );

    always #1 clk = ~clk;

    function [7:0] source_gray;
        input integer I_x;
        input integer I_y;
        input integer I_frame;
        begin
            source_gray = (I_x + I_y + I_frame * 17) & 255;
        end
    endfunction

    function integer expected_cell;
        input integer I_frame;
        input integer I_cnn_x;
        input integer I_cnn_y;
        integer row_start;
        integer row_end;
        integer row;
        integer source_group;
        integer col;
        integer sum;
        begin
            row_start = (I_cnn_y * IMG_HEIGHT) / CNN_SIZE;
            row_end   = (((I_cnn_y + 1) * IMG_HEIGHT) / CNN_SIZE) - 1;
            sum = 0;
            for (row = row_start; row <= row_end; row = row + 1)
                for (source_group = 0; source_group < 5; source_group = source_group + 1)
                    for (col = 0; col < 4; col = col + 1)
                        sum = sum + source_gray(I_cnn_x * 20 + source_group * 4 + col,
                                                row, I_frame);
            expected_cell = sum / (20 * (row_end - row_start + 1));
        end
    endfunction

    task send_frame;
        input integer I_frame;
        begin
            for (source_y = 0; source_y < IMG_HEIGHT; source_y = source_y + 1) begin
                for (x_group = 0; x_group < GROUPS; x_group = x_group + 1) begin
                    @(negedge clk);
                    tvalid   = 1'b1;
                    tuser    = (source_y == 0) && (x_group == 0);
                    tlast    = (x_group == GROUPS - 1);
                    gray_data = {
                        source_gray(x_group * 4 + 3, source_y, I_frame),
                        source_gray(x_group * 4 + 2, source_y, I_frame),
                        source_gray(x_group * 4 + 1, source_y, I_frame),
                        source_gray(x_group * 4 + 0, source_y, I_frame)
                    };
                    @(posedge clk);
                end
            end
            @(negedge clk);
            tvalid    = 1'b0;
            tuser     = 1'b0;
            tlast     = 1'b0;
            gray_data = 32'd0;
        end
    endtask

    // 启动只能发生在整帧输入完成后。第一次启动后锁住RAM0，
    // 用RAM1接收下一帧，再验证第三帧被完整丢弃。
    always @(posedge clk) begin
        if (rst_n && core_start) begin
            start_count = start_count + 1;
            if ((start_count == 1) && !frame0_finished) begin
                $display("[FAIL] CNN started before frame 0 completed");
                error_count = error_count + 1;
            end
            if ((start_count == 2) && !frame1_finished) begin
                $display("[FAIL] CNN started before frame 1 completed");
                error_count = error_count + 1;
            end
            if (start_count == 1) begin
                if (core_input_bank !== 1'b0) begin
                    $display("[FAIL] frame 0 selected bank=%0d", core_input_bank);
                    error_count = error_count + 1;
                end
                core_busy = 1'b1;
            end
            else if (start_count == 2) begin
                if (core_input_bank !== 1'b1) begin
                    $display("[FAIL] frame 1 selected bank=%0d", core_input_bank);
                    error_count = error_count + 1;
                end
                core_busy = 1'b1;
            end
            else begin
                $display("[FAIL] unexpected CNN start count=%0d", start_count);
                error_count = error_count + 1;
            end
        end
    end

    initial begin
        clk             = 1'b0;
        rst_n           = 1'b0;
        tuser           = 1'b0;
        tlast           = 1'b0;
        tvalid          = 1'b0;
        gray_data       = 32'd0;
        core_busy       = 1'b0;
        core_done       = 1'b0;
        core_bank       = 1'b0;
        core_rd_bank    = 1'b0;
        core_rd_addr    = 12'd0;
        error_count     = 0;
        start_count     = 0;
        frame0_finished = 1'b0;
        frame1_finished = 1'b0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;

        send_frame(0);
        frame0_finished = 1'b1;
        wait_count = 0;
        while ((start_count < 1) && (wait_count < 20)) begin
            @(posedge clk);
            wait_count = wait_count + 1;
        end
        if (start_count < 1) begin
            $display("[FAIL] CNN did not start from frame 0");
            error_count = error_count + 1;
        end

        send_frame(1);
        frame1_finished = 1'b1;
        repeat (4) @(posedge clk);
        if (!core_frame_ready) begin
            $display("[FAIL] frame 1 did not become READY while bank 0 was running");
            error_count = error_count + 1;
        end

        send_frame(2);
        repeat (4) @(posedge clk);
        if (!frame_drop) begin
            $display("[FAIL] frame 2 was not marked as dropped when both banks were occupied");
            error_count = error_count + 1;
        end

        // 第三帧不能覆盖第二帧已经READY的RAM1。
        for (address = 0; address < 4096; address = address + 1) begin
            if (dut.u_cnn_input_bank1.mem[address] !==
                expected_cell(1, address % CNN_SIZE, address / CNN_SIZE)) begin
                $display("[FAIL] bank 1 overwritten at address=%0d got=%0d expected=%0d",
                         address, dut.u_cnn_input_bank1.mem[address],
                         expected_cell(1, address % CNN_SIZE, address / CNN_SIZE));
                error_count = error_count + 1;
            end
        end

        // 释放RAM0后，READY的RAM1必须被启动，且不能产生第三次启动。
        @(negedge clk);
        core_bank = 1'b0;
        core_done = 1'b1;
        core_busy = 1'b0;
        @(negedge clk);
        core_done = 1'b0;
        wait_count = 0;
        while ((start_count < 2) && (wait_count < 20)) begin
            @(posedge clk);
            wait_count = wait_count + 1;
        end
        if (start_count < 2) begin
            $display("[FAIL] READY bank 1 did not start after bank 0 completed");
            error_count = error_count + 1;
        end

        repeat (4) @(posedge clk);
        if (start_count != 2) begin
            $display("[FAIL] unexpected extra CNN start count=%0d", start_count);
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("[RESULT] CNN INPUT SAMPLER DOUBLE BUFFER TEST PASSED");
        else
            $fatal(1,"CNN INPUT SAMPLER DOUBLE BUFFER FAILURES=%0d", error_count);
        $finish;
    end

endmodule
