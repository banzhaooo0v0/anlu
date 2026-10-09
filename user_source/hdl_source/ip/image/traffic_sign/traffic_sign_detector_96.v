`timescale 1ns / 1ps

// 蓝底白箭头圆牌的低资源流式识别器。
//
// 识别路径为：RGB 蓝色差分分割 -> 单候选外接框 -> 下一帧 ROI 白像素左右投票。
// 每帧只保存一个候选框和三个计数器，不使用连通域标签、并查集或动态数组索引。
// 因此分离的蓝色区域会合并为同一候选框；宽高比和面积阈值用于拒绝明显错误候选。
module traffic_sign_detector_96 #(
    parameter integer IMG_WIDTH  = 1280,
    parameter integer IMG_HEIGHT = 720
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire        I_tvalid,
    input  wire [95:0] I_tdata,
    output reg         O_busy,
    output reg         O_done,
    output reg         O_result_valid,
    output reg  [4:0]  O_result_class,
    output reg  [7:0]  O_result_ascii,
    output reg         O_frame_drop
);

    // 1280 pixels require 320 four-pixel groups (9 address bits).
    localparam integer X_GROUP_BITS = (IMG_WIDTH / 4 > 1) ? $clog2(IMG_WIDTH / 4) : 1;
    localparam integer MIN_AREA    = 64;
    localparam integer MIN_WIDTH   = 8;
    localparam integer MIN_HEIGHT  = 8;
    localparam integer MIN_WHITE   = 16;
    localparam integer DIFF_MARGIN = 8;

    localparam [4:0] CLASS_UNKNOWN = 5'd0;
    localparam [4:0] CLASS_LEFT    = 5'd1;
    localparam [4:0] CLASS_RIGHT   = 5'd2;

    // 当前帧的蓝色候选外接框和蓝色像素数。
    reg        candidate_valid;
    reg [19:0] candidate_area;
    reg [10:0] candidate_x_min;
    reg [10:0] candidate_x_max;
    reg [9:0]  candidate_y_min;
    reg [9:0]  candidate_y_max;

    // 上一帧确认的候选框，在当前帧中统计白色箭头方向。
    reg        track_valid;
    reg [10:0] track_x_min;
    reg [10:0] track_x_max;
    reg [9:0]  track_y_min;
    reg [9:0]  track_y_max;
    reg [20:0] white_left_count;
    reg [20:0] white_right_count;

    reg [X_GROUP_BITS-1:0] x_group;
    reg [9:0] y_pos;

    // 输入寄存器把颜色判定和候选框更新分为两个时钟级。
    // 该级只增加一个像素组延迟；帧结束标记随数据一起传递。
    reg        pixel_stage_valid;
    reg        pixel_stage_tuser;
    reg        pixel_stage_tlast;
    reg [95:0] pixel_stage_data;

    // 特征级隔离颜色比较。候选框更新只使用已寄存的蓝色掩码和坐标。
    reg        feature_stage_valid;
    reg        feature_stage_tuser;
    reg        feature_stage_tlast;
    reg [X_GROUP_BITS-1:0]  feature_stage_x;
    reg [9:0]  feature_stage_y;
    reg [95:0] feature_stage_data;
    reg        feature_blue_valid;
    reg [2:0]  feature_blue_count;
    reg [10:0] feature_blue_x_min;
    reg [10:0] feature_blue_x_max;

    // 结果级在帧尾锁存左右白色像素总数。分类输出不再直接读取
    // ROI 统计加法链，降低帧尾结果寄存器的建立时间压力。
    reg        result_stage_valid;
    reg        result_stage_track_valid;
    reg [21:0] result_stage_left_total;
    reg [21:0] result_stage_right_total;

    wire [X_GROUP_BITS-1:0] active_x = pixel_stage_tuser ? 8'd0 : x_group;
    wire [9:0] active_y = pixel_stage_tuser ? 10'd0 : y_pos;
    wire [10:0] word_x_base = {active_x, 2'b00};
    wire [10:0] feature_word_x_base = {feature_stage_x, 2'b00};
    wire frame_end = feature_stage_valid && feature_stage_tlast && (feature_stage_y == IMG_HEIGHT - 1);

    function F_blue_pixel;
        input [23:0] pixel;
        integer red;
        integer green;
        integer blue;
        begin
            red   = pixel[23:16];
            green = pixel[15:8];
            blue  = pixel[7:0];
            F_blue_pixel = (blue >= 8'd70) && (blue > red + 20) &&
                           (blue > green + 10) && (green > red - 30);
        end
    endfunction

    function F_white_pixel;
        input [23:0] pixel;
        integer red;
        integer green;
        integer blue;
        begin
            red   = pixel[23:16];
            green = pixel[15:8];
            blue  = pixel[7:0];
            F_white_pixel = (red >= 8'd150) && (green >= 8'd150) &&
                            (blue >= 8'd150) &&
                            ((red - green < 40) && (green - red < 40)) &&
                            ((red - blue < 40) && (blue - red < 40));
        end
    endfunction

    function [2:0] F_count4;
        input [3:0] bits;
        begin
            F_count4 = bits[0] + bits[1] + bits[2] + bits[3];
        end
    endfunction

    function [1:0] F_first_set;
        input [3:0] bits;
        begin
            if (bits[0])
                F_first_set = 2'd0;
            else if (bits[1])
                F_first_set = 2'd1;
            else if (bits[2])
                F_first_set = 2'd2;
            else
                F_first_set = 2'd3;
        end
    endfunction

    function [1:0] F_last_set;
        input [3:0] bits;
        begin
            if (bits[3])
                F_last_set = 2'd3;
            else if (bits[2])
                F_last_set = 2'd2;
            else if (bits[1])
                F_last_set = 2'd1;
            else
                F_last_set = 2'd0;
        end
    endfunction

    wire [3:0] blue_mask = {
        F_blue_pixel(pixel_stage_data[95:72]),
        F_blue_pixel(pixel_stage_data[71:48]),
        F_blue_pixel(pixel_stage_data[47:24]),
        F_blue_pixel(pixel_stage_data[23:0])
    };
    wire blue_word_valid = |blue_mask;
    wire [2:0] blue_word_count = F_count4(blue_mask);
    wire [10:0] blue_word_x_min = word_x_base + F_first_set(blue_mask);
    wire [10:0] blue_word_x_max = word_x_base + F_last_set(blue_mask);

    // tuser 同时是本帧首拍；首拍必须忽略上一帧未清空的候选状态。
    wire candidate_base_valid = feature_stage_tuser ? 1'b0 : candidate_valid;
    wire [19:0] candidate_base_area = feature_stage_tuser ? 20'd0 : candidate_area;
    wire [10:0] candidate_base_x_min = feature_stage_tuser ? 11'd0 : candidate_x_min;
    wire [10:0] candidate_base_x_max = feature_stage_tuser ? 11'd0 : candidate_x_max;
    wire [9:0] candidate_base_y_min = feature_stage_tuser ? 10'd0 : candidate_y_min;
    wire [9:0] candidate_base_y_max = feature_stage_tuser ? 10'd0 : candidate_y_max;

    wire candidate_after_valid = candidate_base_valid || feature_blue_valid;
    wire [20:0] candidate_after_area = candidate_base_area + feature_blue_count;
    wire [10:0] candidate_after_x_min = !candidate_base_valid ? feature_blue_x_min :
                                          !feature_blue_valid ? candidate_base_x_min :
                                          (feature_blue_x_min < candidate_base_x_min ?
                                           feature_blue_x_min : candidate_base_x_min);
    wire [10:0] candidate_after_x_max = !candidate_base_valid ? feature_blue_x_max :
                                          !feature_blue_valid ? candidate_base_x_max :
                                          (feature_blue_x_max > candidate_base_x_max ?
                                           feature_blue_x_max : candidate_base_x_max);
    wire [9:0] candidate_after_y_min = !candidate_base_valid ? feature_stage_y :
                                         !feature_blue_valid ? candidate_base_y_min :
                                         (feature_stage_y < candidate_base_y_min ?
                                          feature_stage_y : candidate_base_y_min);
    wire [9:0] candidate_after_y_max = !candidate_base_valid ? feature_stage_y :
                                         !feature_blue_valid ? candidate_base_y_max :
                                         (feature_stage_y > candidate_base_y_max ?
                                          feature_stage_y : candidate_base_y_max);
    wire [11:0] candidate_width = candidate_after_x_max - candidate_after_x_min + 1'b1;
    wire [10:0] candidate_height = candidate_after_y_max - candidate_after_y_min + 1'b1;
    wire candidate_qualified = candidate_after_valid &&
                               (candidate_after_area >= MIN_AREA) &&
                               (candidate_width >= MIN_WIDTH) &&
                               (candidate_height >= MIN_HEIGHT) &&
                               (candidate_width <= candidate_height * 2) &&
                               (candidate_height <= candidate_width * 2);

    wire track_y_match = track_valid && (feature_stage_y >= track_y_min) &&
                         (feature_stage_y <= track_y_max);
    wire [11:0] track_x_sum = {1'b0, track_x_min} + {1'b0, track_x_max};
    wire [3:0] white_roi_mask = {
        track_y_match && (feature_word_x_base + 11'd3 >= track_x_min) &&
                         (feature_word_x_base + 11'd3 <= track_x_max) && F_white_pixel(feature_stage_data[95:72]),
        track_y_match && (feature_word_x_base + 11'd2 >= track_x_min) &&
                         (feature_word_x_base + 11'd2 <= track_x_max) && F_white_pixel(feature_stage_data[71:48]),
        track_y_match && (feature_word_x_base + 11'd1 >= track_x_min) &&
                         (feature_word_x_base + 11'd1 <= track_x_max) && F_white_pixel(feature_stage_data[47:24]),
        track_y_match && (feature_word_x_base >= track_x_min) &&
                         (feature_word_x_base <= track_x_max) && F_white_pixel(feature_stage_data[23:0])
    };
    wire [3:0] white_left_mask = {
        white_roi_mask[3] && ({feature_word_x_base + 11'd3, 1'b0} <= track_x_sum),
        white_roi_mask[2] && ({feature_word_x_base + 11'd2, 1'b0} <= track_x_sum),
        white_roi_mask[1] && ({feature_word_x_base + 11'd1, 1'b0} <= track_x_sum),
        white_roi_mask[0] && ({feature_word_x_base, 1'b0} <= track_x_sum)
    };
    wire [3:0] white_right_mask = white_roi_mask & ~white_left_mask;
    wire [2:0] white_left_add = F_count4(white_left_mask);
    wire [2:0] white_right_add = F_count4(white_right_mask);
    wire [21:0] white_left_total = white_left_count + white_left_add;
    wire [21:0] white_right_total = white_right_count + white_right_add;
    wire [21:0] white_difference = (white_left_total >= white_right_total) ?
                                  (white_left_total - white_right_total) :
                                  (white_right_total - white_left_total);

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            candidate_valid   <= 1'b0;
            candidate_area    <= 20'd0;
            candidate_x_min   <= 11'd0;
            candidate_x_max   <= 11'd0;
            candidate_y_min   <= 10'd0;
            candidate_y_max   <= 10'd0;
            track_valid       <= 1'b0;
            track_x_min       <= 11'd0;
            track_x_max       <= 11'd0;
            track_y_min       <= 10'd0;
            track_y_max       <= 10'd0;
            white_left_count  <= 21'd0;
            white_right_count <= 21'd0;
            x_group           <= 8'd0;
            y_pos             <= 10'd0;
            pixel_stage_valid <= 1'b0;
            pixel_stage_tuser <= 1'b0;
            pixel_stage_tlast <= 1'b0;
            pixel_stage_data  <= 96'd0;
            feature_stage_valid <= 1'b0;
            feature_stage_tuser <= 1'b0;
            feature_stage_tlast <= 1'b0;
            feature_stage_x <= 8'd0;
            feature_stage_y <= 10'd0;
            feature_stage_data <= 96'd0;
            feature_blue_valid <= 1'b0;
            feature_blue_count <= 3'd0;
            feature_blue_x_min <= 11'd0;
            feature_blue_x_max <= 11'd0;
            result_stage_valid <= 1'b0;
            result_stage_track_valid <= 1'b0;
            result_stage_left_total <= 22'd0;
            result_stage_right_total <= 22'd0;
            O_busy            <= 1'b0;
            O_done            <= 1'b0;
            O_result_valid    <= 1'b0;
            O_result_class    <= CLASS_UNKNOWN;
            O_result_ascii    <= "?";
            O_frame_drop      <= 1'b0;
        end
        else begin
            O_done         <= 1'b0;
            O_result_valid <= 1'b0;
            O_frame_drop   <= 1'b0;
            result_stage_valid <= 1'b0;

            pixel_stage_valid <= I_tvalid;
            pixel_stage_tuser <= I_tvalid && I_tuser;
            pixel_stage_tlast <= I_tvalid && I_tlast;
            if (I_tvalid)
                pixel_stage_data <= I_tdata;

            feature_stage_valid <= pixel_stage_valid;
            feature_stage_tuser <= pixel_stage_valid && pixel_stage_tuser;
            feature_stage_tlast <= pixel_stage_valid && pixel_stage_tlast;
            feature_stage_x <= active_x;
            feature_stage_y <= active_y;
            feature_stage_data <= pixel_stage_data;
            feature_blue_valid <= blue_word_valid;
            feature_blue_count <= blue_word_count;
            feature_blue_x_min <= blue_word_x_min;
            feature_blue_x_max <= blue_word_x_max;

            if (pixel_stage_valid) begin
                if (pixel_stage_tlast) begin
                    x_group <= 8'd0;
                    y_pos <= (active_y == IMG_HEIGHT - 1) ? 10'd0 : active_y + 10'd1;
                end
                else begin
                    x_group <= active_x + 8'd1;
                end
            end

            if (feature_stage_valid) begin
                if (feature_stage_tuser) begin
                    O_busy <= 1'b1;
                    white_left_count  <= 21'd0;
                    white_right_count <= 21'd0;
                end

                if (frame_end) begin
                    O_busy         <= 1'b0;
                    result_stage_valid <= 1'b1;
                    result_stage_track_valid <= track_valid;
                    result_stage_left_total <= white_left_total;
                    result_stage_right_total <= white_right_total;

                    if (candidate_qualified) begin
                        track_valid <= 1'b1;
                        track_x_min <= candidate_after_x_min;
                        track_x_max <= candidate_after_x_max;
                        track_y_min <= candidate_after_y_min;
                        track_y_max <= candidate_after_y_max;
                    end
                    else begin
                        track_valid <= 1'b0;
                    end

                    candidate_valid   <= 1'b0;
                    candidate_area    <= 20'd0;
                    white_left_count  <= 21'd0;
                    white_right_count <= 21'd0;
                end
                else begin
                    candidate_valid <= candidate_after_valid;
                    candidate_area  <= candidate_after_area[19:0];
                    candidate_x_min <= candidate_after_x_min;
                    candidate_x_max <= candidate_after_x_max;
                    candidate_y_min <= candidate_after_y_min;
                    candidate_y_max <= candidate_after_y_max;

                    if (track_valid) begin
                        white_left_count  <= white_left_total[20:0];
                        white_right_count <= white_right_total[20:0];
                    end

                end
            end

            if (result_stage_valid) begin
                O_done         <= 1'b1;
                O_result_valid <= 1'b1;
                if (!result_stage_track_valid ||
                    (result_stage_left_total + result_stage_right_total < MIN_WHITE) ||
                    ((result_stage_left_total >= result_stage_right_total ?
                      result_stage_left_total - result_stage_right_total :
                      result_stage_right_total - result_stage_left_total) < DIFF_MARGIN)) begin
                    O_result_class <= CLASS_UNKNOWN;
                    O_result_ascii <= "?";
                end
                else if (result_stage_left_total > result_stage_right_total) begin
                    O_result_class <= CLASS_LEFT;
                    O_result_ascii <= "L";
                end
                else begin
                    O_result_class <= CLASS_RIGHT;
                    O_result_ascii <= "R";
                end
            end
        end
    end

endmodule
