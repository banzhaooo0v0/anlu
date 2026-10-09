`timescale 1ns/1ps

// 验证1024x600四像素灰度流到64x64输入图的坐标和平均值。
module tb_cnn_input_sampler_96;

    localparam integer IMG_WIDTH  = 1024;
    localparam integer IMG_HEIGHT = 600;
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
    integer x_group;
    integer source_y;
    integer cnn_x;
    integer cnn_y;
    integer row_start;
    integer row_end;
    integer row;
    integer source_group;
    integer col;
    integer source_sum;
    integer expected_value;
    reg [7:0] got_value;

    cnn_input_sampler_96 #(.IMG_WIDTH(1024),.IMG_HEIGHT(600)) dut (
        .I_clk                   (clk),
        .I_rst_n                 (rst_n),
        .I_tuser                 (tuser),
        .I_tlast                 (tlast),
        .I_tvalid                (tvalid),
        .I_gray_data             (gray_data),
        .I_core_busy             (core_busy),
        .I_core_done             (core_done),
        .I_core_bank             (core_bank),
        .O_core_start            (core_start),
        .O_core_input_bank       (core_input_bank),
        .O_core_input_frame_ready(core_frame_ready),
        .I_core_rd_bank          (core_rd_bank),
        .I_core_rd_addr          (core_rd_addr),
        .O_core_rd_data          (core_rd_data),
        .O_frame_drop            (frame_drop),
        .O_capture_active        ()
    );

    always #1 clk = ~clk;

    function [7:0] source_gray;
        input integer I_x_group;
        input integer I_y;
        begin
            source_gray = (I_x_group + I_y) & 255;
        end
    endfunction

    task send_frame;
        begin
            for (source_y = 0; source_y < IMG_HEIGHT; source_y = source_y + 1) begin
                for (x_group = 0; x_group < GROUPS; x_group = x_group + 1) begin
                    @(negedge clk);
                    tvalid = 1'b1;
                    tuser = (source_y == 0) && (x_group == 0);
                    tlast = (x_group == GROUPS - 1);
                    gray_data = {
                        source_gray(x_group * 4 + 3, source_y),
                        source_gray(x_group * 4 + 2, source_y),
                        source_gray(x_group * 4 + 1, source_y),
                        source_gray(x_group * 4 + 0, source_y)
                    };
                    @(posedge clk);
                end
            end
            @(negedge clk);
            tvalid = 1'b0;
            tuser = 1'b0;
            tlast = 1'b0;
            gray_data = 32'd0;
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tuser = 1'b0;
        tlast = 1'b0;
        tvalid = 1'b0;
        gray_data = 32'd0;
        core_busy = 1'b1;
        core_done = 1'b0;
        core_bank = 1'b0;
        core_rd_bank = 1'b0;
        core_rd_addr = 12'd0;
        error_count = 0;

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        send_frame;
        repeat (4) @(posedge clk);

        if (!core_frame_ready) begin
            $display("[FAIL] completed input frame is not READY");
            error_count = error_count + 1;
        end
        if (frame_drop) begin
            $display("[FAIL] input sampler asserted frame_drop");
            error_count = error_count + 1;
        end

        // 逐点检查RAM0。每个CNN点覆盖4个源组、16个源像素和9/10个源行。
        for (cnn_y = 0; cnn_y < CNN_SIZE; cnn_y = cnn_y + 1) begin
            row_start = (cnn_y * IMG_HEIGHT) / CNN_SIZE;
            row_end = (((cnn_y + 1) * IMG_HEIGHT) / CNN_SIZE) - 1;
            for (cnn_x = 0; cnn_x < CNN_SIZE; cnn_x = cnn_x + 1) begin
                source_sum = 0;
                for (row = row_start; row <= row_end; row = row + 1)
                    for (source_group = 0; source_group < 4; source_group = source_group + 1)
                        for (col = 0; col < 4; col = col + 1)
                            source_sum = source_sum + source_gray(cnn_x * 16 + source_group * 4 + col, row);
                expected_value = source_sum / (16 * (row_end - row_start + 1));
                got_value = dut.u_cnn_input_bank0.mem[cnn_y * CNN_SIZE + cnn_x];
                if (got_value !== expected_value[7:0]) begin
                    $display("[FAIL] cnn=(%0d,%0d) got=%0d expected=%0d rows=%0d..%0d",
                             cnn_x, cnn_y, got_value, expected_value,
                             row_start, row_end);
                    error_count = error_count + 1;
                end
            end
        end

        if (error_count == 0)
            $display("[RESULT] CNN INPUT SAMPLER TEST PASSED");
        else
            $display("[RESULT] CNN INPUT SAMPLER FAILURES=%0d", error_count);
        $finish;
    end

endmodule
