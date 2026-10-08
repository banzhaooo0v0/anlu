`timescale 1ns/1ps

// 验证默认1280x720视频尺寸下的整帧计数和标记对齐。
// 算法数值由小尺寸回归用例覆盖，本用例重点检查固定速率链路的吞吐量。
module tb_image_process_stream_96_full;

    localparam integer IMG_WIDTH  = 1280;
    localparam integer IMG_HEIGHT = 720;
    localparam integer GROUPS     = IMG_WIDTH / 4;
    localparam integer FRAME_BEATS = GROUPS * IMG_HEIGHT;
    localparam integer MODE_COUNT = 4;
    localparam [1:0] MODE_CNN      = 2'b00;
    localparam [1:0] MODE_DILATION = 2'b01;
    localparam [1:0] MODE_EROSION  = 2'b10;
    localparam [1:0] MODE_RAW      = 2'b11;

    reg         clk;
    reg         rst_n;
    reg         i_tuser;
    reg         i_tlast;
    reg         i_tvalid;
    reg  [95:0] i_tdata;
    reg  [1:0]  algo_mode;
    reg  [10:0] edge_threshold;

    wire        o_tuser;
    wire        o_tlast;
    wire        o_tvalid;
    wire [95:0] o_tdata;
    wire        o_gray_tuser;
    wire        o_gray_tlast;
    wire        o_gray_tvalid;
    wire [31:0] o_gray_data;
    wire [1:0]  o_gray_mode;

    reg         expected_valid [0:3];
    reg         expected_user  [0:3];
    reg         expected_last  [0:3];
    reg  [95:0] expected_data  [0:3];
    reg         expected_raw   [0:3];
    integer     output_beats;
    integer     output_users;
    integer     output_lasts;
    integer     error_count;
    integer     frame_index;
    integer     x_group;
    integer     y;
    integer     pipe_index;
    reg  [1:0]  current_mode;

    image_process_stream_96 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) dut (
        .I_clk           (clk),
        .I_rst_n         (rst_n),
        .I_tuser         (i_tuser),
        .I_tlast         (i_tlast),
        .I_tvalid        (i_tvalid),
        .I_tdata         (i_tdata),
        .I_algo_mode     (algo_mode),
        .I_edge_threshold(edge_threshold),
        .O_tuser         (o_tuser),
        .O_tlast         (o_tlast),
        .O_tvalid        (o_tvalid),
        .O_tdata         (o_tdata),
        .O_gray_tuser    (o_gray_tuser),
        .O_gray_tlast    (o_gray_tlast),
        .O_gray_tvalid   (o_gray_tvalid),
        .O_gray_data     (o_gray_data),
        .O_gray_mode     (o_gray_mode)
    );

    always #5 clk = ~clk;

    function [95:0] make_input_word;
        input integer I_x;
        input integer I_y;
        input integer I_frame;
        reg [23:0] pixel_0;
        reg [23:0] pixel_1;
        reg [23:0] pixel_2;
        reg [23:0] pixel_3;
        integer seed;
        begin
            seed = I_frame * 17 + I_x * 5 + I_y * 3;
            pixel_0 = {8'(seed + 11), 8'(seed + 23), 8'(seed + 37)};
            pixel_1 = {8'(seed + 41), 8'(seed + 53), 8'(seed + 67)};
            pixel_2 = {8'(seed + 71), 8'(seed + 83), 8'(seed + 97)};
            pixel_3 = {8'(seed + 101), 8'(seed + 113), 8'(seed + 127)};
            make_input_word = {pixel_3, pixel_2, pixel_1, pixel_0};
        end
    endfunction

    task check_output;
        begin
            #1;
            if (o_tvalid !== expected_valid[2]) begin
                $display("[FAIL] valid alignment frame=%0d x=%0d y=%0d got=%b expected=%b",
                         frame_index, x_group, y, o_tvalid, expected_valid[2]);
                error_count = error_count + 1;
            end
            if (o_tvalid) begin
                output_beats = output_beats + 1;
                if (o_tuser !== expected_user[2]) begin
                    $display("[FAIL] tuser alignment beat=%0d", output_beats);
                    error_count = error_count + 1;
                end
                if (o_tlast !== expected_last[2]) begin
                    $display("[FAIL] tlast alignment beat=%0d", output_beats);
                    error_count = error_count + 1;
                end
                if (o_tuser)
                    output_users = output_users + 1;
                if (o_tlast)
                    output_lasts = output_lasts + 1;
                if (expected_raw[2] && (o_tdata !== expected_data[2])) begin
                    $display("[FAIL] raw data mismatch beat=%0d got=%h expected=%h",
                             output_beats, o_tdata, expected_data[2]);
                    error_count = error_count + 1;
                end
            end
            if (o_gray_tvalid !== expected_valid[2] ||
                o_gray_tuser  !== expected_user[2]  ||
                o_gray_tlast  !== expected_last[2]) begin
                $display("[FAIL] gray sideband marker mismatch beat=%0d", output_beats);
                error_count = error_count + 1;
            end

            // DUT 有灰度、窗口和 Sobel 三个寄存器级。当前输出与前三拍输入比较。
            expected_valid[2] = expected_valid[1];
            expected_user[2]  = expected_user[1];
            expected_last[2]  = expected_last[1];
            expected_data[2]  = expected_data[1];
            expected_raw[2]   = expected_raw[1];
            expected_valid[1] = expected_valid[0];
            expected_user[1]  = expected_user[0];
            expected_last[1]  = expected_last[0];
            expected_data[1]  = expected_data[0];
            expected_raw[1]   = expected_raw[0];
            expected_valid[0] = i_tvalid;
            expected_user[0]  = i_tuser;
            expected_last[0]  = i_tlast;
            expected_data[0]  = i_tdata;
            expected_raw[0]   = i_tvalid && (current_mode == MODE_RAW);

        end
    endtask

    task run_frame;
        input [1:0] I_mode;
        begin
            current_mode = I_mode;
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                for (x_group = 0; x_group < GROUPS; x_group = x_group + 1) begin
                    @(negedge clk);
                    i_tvalid = 1'b1;
                    i_tuser  = (x_group == 0) && (y == 0);
                    i_tlast  = (x_group == GROUPS - 1);
                    i_tdata  = make_input_word(x_group, y, frame_index);
                    algo_mode = I_mode;
                    edge_threshold = 11'd24;
                    @(posedge clk);
                    check_output;
                end
            end
            frame_index = frame_index + 1;
        end
    endtask

    integer checked_groups = 0;
    always @(negedge clk) if (rst_n && dut.window_stage_valid) begin
        if (dut.window_stage_x !== (checked_groups % GROUPS))
            $fatal(1,"line-store coordinate wrap: got=%0d expected=%0d",dut.window_stage_x,checked_groups % GROUPS);
        checked_groups = checked_groups + 1;
    end

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        i_tuser = 1'b0;
        i_tlast = 1'b0;
        i_tvalid = 1'b0;
        i_tdata = 96'd0;
        algo_mode = MODE_RAW;
        edge_threshold = 11'd24;
        output_beats = 0;
        output_users = 0;
        output_lasts = 0;
        error_count = 0;
        frame_index = 0;
        current_mode = MODE_RAW;
        for (pipe_index = 0; pipe_index < 4; pipe_index = pipe_index + 1) begin
            expected_valid[pipe_index] = 1'b0;
            expected_user[pipe_index]  = 1'b0;
            expected_last[pipe_index]  = 1'b0;
            expected_data[pipe_index]  = 96'd0;
            expected_raw[pipe_index]   = 1'b0;
        end

        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        run_frame(MODE_RAW);
        run_frame(MODE_EROSION);
        run_frame(MODE_DILATION);
        run_frame(MODE_CNN);

        @(negedge clk);
        i_tvalid = 1'b0;
        i_tuser  = 1'b0;
        i_tlast  = 1'b0;
        repeat (8) begin
            @(posedge clk);
            check_output;
        end

        if (output_beats !== FRAME_BEATS * MODE_COUNT) begin
            $display("[FAIL] output beats=%0d expected=%0d", output_beats,
                     FRAME_BEATS * MODE_COUNT);
            error_count = error_count + 1;
        end
        if (output_users !== MODE_COUNT) begin
            $display("[FAIL] output tuser count=%0d expected=%0d", output_users, MODE_COUNT);
            error_count = error_count + 1;
        end
        if (output_lasts !== IMG_HEIGHT * MODE_COUNT) begin
            $display("[FAIL] output tlast count=%0d expected=%0d", output_lasts,
                     IMG_HEIGHT * MODE_COUNT);
            error_count = error_count + 1;
        end

        if (error_count == 0)
            $display("[RESULT] FULL FRAME STREAM TEST PASSED beats=%0d tuser=%0d tlast=%0d",
                     output_beats, output_users, output_lasts);
        else
            $fatal(1,"[RESULT] FULL FRAME STREAM FAILURES=%0d", error_count);
        $finish;
    end

endmodule
