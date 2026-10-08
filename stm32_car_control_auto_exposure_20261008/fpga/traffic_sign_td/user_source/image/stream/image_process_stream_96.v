`timescale 1ns / 1ps

// 四像素并行的灰度、Sobel 和形态学流处理。
//
// 每个输入拍包含四个连续像素。行缓存按四像素打包，横向窗口使用
// 当前组和前一组的移位数据，因此组边界不会把四个像素错误地合并。
// 窗口采用“当前像素为右下角”的因果 3x3 窗口，边界补零。
module image_process_stream_96 #(
    parameter integer IMG_WIDTH  = 1280,
    parameter integer IMG_HEIGHT = 720
) (
    input  wire        I_clk,
    input  wire        I_rst_n,
    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire        I_tvalid,
    input  wire [95:0] I_tdata,
    input  wire [1:0]  I_algo_mode,
    input  wire [10:0] I_edge_threshold,
    output reg         O_tuser,
    output reg         O_tlast,
    output reg         O_tvalid,
    output reg  [95:0] O_tdata,
    output reg         O_gray_tuser,
    output reg         O_gray_tlast,
    output reg         O_gray_tvalid,
    output reg  [31:0] O_gray_data,
    output reg  [1:0]  O_gray_mode
);

    // 1280 pixels require 320 four-pixel groups (9 address bits).
    localparam integer X_GROUP_BITS = (IMG_WIDTH / 4 > 1) ? $clog2(IMG_WIDTH / 4) : 1;
    localparam integer GROUP_WIDTH = IMG_WIDTH / 4;
    localparam [1:0] MODE_CNN      = 2'b00;
    localparam [1:0] MODE_DILATION = 2'b01;
    localparam [1:0] MODE_EROSION  = 2'b10;
    localparam [1:0] MODE_RAW      = 2'b11;

    // These line stores do not need reset values.  The y-position guards
    // prevent reads before the current frame has written the required lines.
    // Removing asynchronous reset lets TD infer memory instead of thousands
    // of individual resettable flip-flops.
    (* ram_style = "block" *) reg [31:0] gray_line_a [0:GROUP_WIDTH-1];
    (* ram_style = "block" *) reg [31:0] gray_line_b [0:GROUP_WIDTH-1];
    (* ram_style = "block" *) reg [3:0]  sobel_line_a[0:GROUP_WIDTH-1];
    (* ram_style = "block" *) reg [3:0]  sobel_line_b[0:GROUP_WIDTH-1];

    reg [31:0] gray_prev_word;
    reg [31:0] gray_top_prev_word;
    reg [31:0] gray_mid_prev_word;
    reg [3:0]  sobel_prev_word;
    reg [3:0]  sobel_top_prev_word;
    reg [3:0]  sobel_mid_prev_word;
    reg [X_GROUP_BITS-1:0]  x_group;
    reg [9:0]  y_pos;
    reg [1:0]  frame_algo_mode;
    reg [10:0] frame_threshold;

    // 灰度级保存每拍输入的灰度和控制信息。Sobel/形态学级只读取
    // 这个寄存器级，避免灰度乘法器直接驱动形态学输出寄存器。
    reg        gray_stage_valid;
    reg        gray_stage_tuser;
    reg        gray_stage_tlast;
    reg [95:0] rgb_stage_data;
    reg [31:0] gray_stage_data;
    reg [1:0]  gray_stage_mode;
    reg [10:0] gray_stage_threshold;

    // 窗口级把行存储器读出和横向移位的结果锁存。Sobel 算法只读取
    // 本级寄存器，避免地址选择、RAM 读出和加法链处于同一时钟路径。
    reg        window_stage_valid;
    reg        window_stage_tuser;
    reg        window_stage_tlast;
    reg [95:0] window_stage_rgb_data;
    reg [31:0] window_stage_gray_data;
    reg [1:0]  window_stage_mode;
    reg [10:0] window_stage_threshold;
    reg [X_GROUP_BITS-1:0]  window_stage_x;
    reg [9:0]  window_stage_y;
    reg [31:0] window_top_l2;
    reg [31:0] window_top_l1;
    reg [31:0] window_top_c;
    reg [31:0] window_mid_l2;
    reg [31:0] window_mid_l1;
    reg [31:0] window_mid_c;
    reg [31:0] window_cur_l2;
    reg [31:0] window_cur_l1;
    reg [31:0] window_cur_c;

    // Sobel 级保存 3x3 灰度窗口的计算结果。形态学级只读取此寄存器，
    // 避免行 RAM 的异步读、四个 Sobel 和形态学逻辑位于同一个时钟路径。
    reg        sobel_stage_valid;
    reg        sobel_stage_tuser;
    reg        sobel_stage_tlast;
    reg [95:0] sobel_stage_rgb_data;
    reg [31:0] sobel_stage_gray_data;
    reg [3:0]  sobel_stage_word;
    reg [1:0]  sobel_stage_mode;
    reg [X_GROUP_BITS-1:0]  sobel_stage_x;
    reg [9:0]  sobel_stage_y;

    wire [X_GROUP_BITS-1:0] gray_active_x = gray_stage_tuser ? 8'd0 : x_group;
    wire [9:0] gray_active_y = gray_stage_tuser ? 10'd0 : y_pos;
    wire [1:0] gray_active_mode = gray_stage_tuser ? gray_stage_mode : frame_algo_mode;
    wire [10:0] gray_active_threshold = gray_stage_tuser ? gray_stage_threshold : frame_threshold;
    wire [X_GROUP_BITS-1:0] morph_active_x = sobel_stage_tuser ? 8'd0 : sobel_stage_x;
    wire [9:0] morph_active_y = sobel_stage_tuser ? 10'd0 : sobel_stage_y;

    function [7:0] F_gray;
        input [7:0] red;
        input [7:0] green;
        input [7:0] blue;
        integer sum;
        begin
            sum = red * 77 + green * 150 + blue * 29;
            F_gray = sum >> 8;
        end
    endfunction

    function [7:0] F_lane8;
        input [31:0] word;
        input integer index;
        begin
            case (index)
                0: F_lane8 = word[7:0];
                1: F_lane8 = word[15:8];
                2: F_lane8 = word[23:16];
                default: F_lane8 = word[31:24];
            endcase
        end
    endfunction

    function F_lane1;
        input [3:0] word;
        input integer index;
        begin
            case (index)
                0: F_lane1 = word[0];
                1: F_lane1 = word[1];
                2: F_lane1 = word[2];
                default: F_lane1 = word[3];
            endcase
        end
    endfunction

    function F_sobel;
        input [7:0] t_l2;
        input [7:0] t_l1;
        input [7:0] t_c;
        input [7:0] m_l2;
        input [7:0] m_l1;
        input [7:0] m_c;
        input [7:0] c_l2;
        input [7:0] c_l1;
        input [7:0] c_c;
        input [10:0] threshold;
        integer gx;
        integer gy;
        begin
            gx = t_c + (m_l1 << 1) + c_c - t_l2 - (m_l2 << 1) - c_l2;
            gy = c_l2 + (c_l1 << 1) + c_c - t_l2 - (t_l1 << 1) - t_c;
            if (gx < 0) gx = -gx;
            if (gy < 0) gy = -gy;
            F_sobel = ((gx + gy) > threshold);
        end
    endfunction

    function F_morph;
        input [8:0] taps;
        input        dilation;
        begin
            F_morph = dilation ? (|taps) : (&taps);
        end
    endfunction

    wire [7:0] input_gray_0 = F_gray(I_tdata[23:16], I_tdata[15:8], I_tdata[7:0]);
    wire [7:0] input_gray_1 = F_gray(I_tdata[47:40], I_tdata[39:32], I_tdata[31:24]);
    wire [7:0] input_gray_2 = F_gray(I_tdata[71:64], I_tdata[63:56], I_tdata[55:48]);
    wire [7:0] input_gray_3 = F_gray(I_tdata[95:88], I_tdata[87:80], I_tdata[79:72]);

    reg [7:0] gray_word[0:3];
    reg [7:0] top_word[0:3];
    reg [7:0] mid_word[0:3];
    reg [7:0] top_l2[0:3];
    reg [7:0] top_l1[0:3];
    reg [7:0] mid_l2[0:3];
    reg [7:0] mid_l1[0:3];
    reg [7:0] cur_l2[0:3];
    reg [7:0] cur_l1[0:3];
    reg [3:0] sobel_word;
    reg [3:0] erosion_word;
    reg [3:0] dilation_word;
    reg [8:0] erosion_taps[0:3];
    reg [8:0] dilation_taps[0:3];
    reg [95:0] selected_data;
    integer lane;

    // 组合窗口。lane 0 和 lane 1 的左侧像素来自上一组。
    always @(*) begin
        gray_word[0] = gray_stage_data[7:0];
        gray_word[1] = gray_stage_data[15:8];
        gray_word[2] = gray_stage_data[23:16];
        gray_word[3] = gray_stage_data[31:24];

        for (lane = 0; lane < 4; lane = lane + 1) begin
            if (gray_active_y == 0) begin
                top_word[lane] = 8'd0;
                mid_word[lane] = 8'd0;
            end
            else if (gray_active_y == 1) begin
                top_word[lane] = 8'd0;
                mid_word[lane] = F_lane8(gray_line_a[gray_active_x], lane);
            end
            else begin
                top_word[lane] = F_lane8(gray_line_b[gray_active_x], lane);
                mid_word[lane] = F_lane8(gray_line_a[gray_active_x], lane);
            end

            if (lane == 0) begin
                top_l2[lane] = (gray_active_x == 0) ? 8'd0 : F_lane8(gray_top_prev_word, 2);
                mid_l2[lane] = (gray_active_x == 0) ? 8'd0 : F_lane8(gray_mid_prev_word, 2);
                cur_l2[lane] = (gray_active_x == 0) ? 8'd0 : F_lane8(gray_prev_word, 2);
                top_l1[lane] = (gray_active_x == 0) ? 8'd0 : F_lane8(gray_top_prev_word, 3);
                mid_l1[lane] = (gray_active_x == 0) ? 8'd0 : F_lane8(gray_mid_prev_word, 3);
                cur_l1[lane] = (gray_active_x == 0) ? 8'd0 : F_lane8(gray_prev_word, 3);
            end
            else if (lane == 1) begin
                top_l2[lane] = (gray_active_x == 0) ? 8'd0 : F_lane8(gray_top_prev_word, 3);
                mid_l2[lane] = (gray_active_x == 0) ? 8'd0 : F_lane8(gray_mid_prev_word, 3);
                cur_l2[lane] = (gray_active_x == 0) ? 8'd0 : F_lane8(gray_prev_word, 3);
                top_l1[lane] = top_word[0];
                mid_l1[lane] = mid_word[0];
                cur_l1[lane] = gray_word[0];
            end
            else begin
                top_l2[lane] = top_word[lane - 2];
                mid_l2[lane] = mid_word[lane - 2];
                cur_l2[lane] = gray_word[lane - 2];
                top_l1[lane] = top_word[lane - 1];
                mid_l1[lane] = mid_word[lane - 1];
                cur_l1[lane] = gray_word[lane - 1];
            end

            sobel_word[lane] = F_sobel(
                F_lane8(window_top_l2, lane), F_lane8(window_top_l1, lane),
                F_lane8(window_top_c, lane), F_lane8(window_mid_l2, lane),
                F_lane8(window_mid_l1, lane), F_lane8(window_mid_c, lane),
                F_lane8(window_cur_l2, lane), F_lane8(window_cur_l1, lane),
                F_lane8(window_cur_c, lane), window_stage_threshold);
        end

        for (lane = 0; lane < 4; lane = lane + 1) begin
            if (morph_active_y < 2) begin
                erosion_taps[lane] = 9'd0;
                dilation_taps[lane] = 9'd0;
            end
            else begin
                erosion_taps[lane] = 9'd0;
                dilation_taps[lane] = 9'd0;
                if (lane == 0) begin
                    erosion_taps[lane][0] = (morph_active_x == 0) ? 1'b0 : F_lane1(sobel_top_prev_word, 2);
                    erosion_taps[lane][1] = (morph_active_x == 0) ? 1'b0 : F_lane1(sobel_top_prev_word, 3);
                    erosion_taps[lane][3] = (morph_active_x == 0) ? 1'b0 : F_lane1(sobel_mid_prev_word, 2);
                    erosion_taps[lane][4] = (morph_active_x == 0) ? 1'b0 : F_lane1(sobel_mid_prev_word, 3);
                    erosion_taps[lane][6] = (morph_active_x == 0) ? 1'b0 : F_lane1(sobel_prev_word, 2);
                    erosion_taps[lane][7] = (morph_active_x == 0) ? 1'b0 : F_lane1(sobel_prev_word, 3);
                end
                else if (lane == 1) begin
                    erosion_taps[lane][0] = (morph_active_x == 0) ? 1'b0 : F_lane1(sobel_top_prev_word, 3);
                    erosion_taps[lane][1] = F_lane1(sobel_line_b[morph_active_x], 0);
                    erosion_taps[lane][3] = (morph_active_x == 0) ? 1'b0 : F_lane1(sobel_mid_prev_word, 3);
                    erosion_taps[lane][4] = F_lane1(sobel_line_a[morph_active_x], 0);
                    erosion_taps[lane][6] = (morph_active_x == 0) ? 1'b0 : F_lane1(sobel_prev_word, 3);
                    erosion_taps[lane][7] = sobel_stage_word[0];
                end
                else begin
                    erosion_taps[lane][0] = F_lane1(sobel_line_b[morph_active_x], lane - 2);
                    erosion_taps[lane][1] = F_lane1(sobel_line_b[morph_active_x], lane - 1);
                    erosion_taps[lane][3] = F_lane1(sobel_line_a[morph_active_x], lane - 2);
                    erosion_taps[lane][4] = F_lane1(sobel_line_a[morph_active_x], lane - 1);
                    erosion_taps[lane][6] = F_lane1(sobel_stage_word, lane - 2);
                    erosion_taps[lane][7] = F_lane1(sobel_stage_word, lane - 1);
                end
                erosion_taps[lane][2] = F_lane1(sobel_line_b[morph_active_x], lane);
                erosion_taps[lane][5] = F_lane1(sobel_line_a[morph_active_x], lane);
                erosion_taps[lane][8] = sobel_stage_word[lane];
                dilation_taps[lane] = erosion_taps[lane];
            end
            erosion_word[lane]  = F_morph(erosion_taps[lane], 1'b0);
            dilation_word[lane] = F_morph(dilation_taps[lane], 1'b1);
        end

        selected_data = sobel_stage_rgb_data;
        if (sobel_stage_mode == MODE_EROSION)
            selected_data = {erosion_word[3] ? 24'hffffff : 24'h000000,
                             erosion_word[2] ? 24'hffffff : 24'h000000,
                             erosion_word[1] ? 24'hffffff : 24'h000000,
                             erosion_word[0] ? 24'hffffff : 24'h000000};
        else if (sobel_stage_mode == MODE_DILATION)
            selected_data = {dilation_word[3] ? 24'hffffff : 24'h000000,
                             dilation_word[2] ? 24'hffffff : 24'h000000,
                             dilation_word[1] ? 24'hffffff : 24'h000000,
                             dilation_word[0] ? 24'hffffff : 24'h000000};
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            x_group          <= 8'd0;
            y_pos            <= 10'd0;
            frame_algo_mode  <= MODE_RAW;
            frame_threshold  <= 11'd24;
            gray_stage_valid <= 1'b0;
            gray_stage_tuser <= 1'b0;
            gray_stage_tlast <= 1'b0;
            rgb_stage_data   <= 96'd0;
            gray_stage_data  <= 32'd0;
            gray_stage_mode  <= MODE_RAW;
            gray_stage_threshold <= 11'd24;
            window_stage_valid <= 1'b0;
            window_stage_tuser <= 1'b0;
            window_stage_tlast <= 1'b0;
            window_stage_rgb_data <= 96'd0;
            window_stage_gray_data <= 32'd0;
            window_stage_mode <= MODE_RAW;
            window_stage_threshold <= 11'd24;
            window_stage_x <= 8'd0;
            window_stage_y <= 10'd0;
            window_top_l2 <= 32'd0;
            window_top_l1 <= 32'd0;
            window_top_c <= 32'd0;
            window_mid_l2 <= 32'd0;
            window_mid_l1 <= 32'd0;
            window_mid_c <= 32'd0;
            window_cur_l2 <= 32'd0;
            window_cur_l1 <= 32'd0;
            window_cur_c <= 32'd0;
            sobel_stage_valid <= 1'b0;
            sobel_stage_tuser <= 1'b0;
            sobel_stage_tlast <= 1'b0;
            sobel_stage_rgb_data <= 96'd0;
            sobel_stage_gray_data <= 32'd0;
            sobel_stage_word <= 4'd0;
            sobel_stage_mode <= MODE_RAW;
            sobel_stage_x <= 8'd0;
            sobel_stage_y <= 10'd0;
            gray_prev_word   <= 32'd0;
            gray_top_prev_word <= 32'd0;
            gray_mid_prev_word <= 32'd0;
            sobel_prev_word  <= 4'd0;
            sobel_top_prev_word <= 4'd0;
            sobel_mid_prev_word <= 4'd0;
            O_tuser          <= 1'b0;
            O_tlast          <= 1'b0;
            O_tvalid         <= 1'b0;
            O_tdata          <= 96'd0;
            O_gray_tuser     <= 1'b0;
            O_gray_tlast     <= 1'b0;
            O_gray_tvalid    <= 1'b0;
            O_gray_data      <= 32'd0;
            O_gray_mode      <= MODE_RAW;
        end
        else begin
            gray_stage_valid <= I_tvalid;
            gray_stage_tuser <= I_tvalid && I_tuser;
            gray_stage_tlast <= I_tvalid && I_tlast;
            rgb_stage_data   <= I_tdata;
            gray_stage_data  <= {input_gray_3, input_gray_2, input_gray_1, input_gray_0};
            gray_stage_mode  <= I_algo_mode;
            gray_stage_threshold <= I_edge_threshold;

            window_stage_valid <= gray_stage_valid;
            window_stage_tuser <= gray_stage_valid && gray_stage_tuser;
            window_stage_tlast <= gray_stage_valid && gray_stage_tlast;
            window_stage_rgb_data <= rgb_stage_data;
            window_stage_gray_data <= {gray_word[3], gray_word[2], gray_word[1], gray_word[0]};
            window_stage_mode <= gray_active_mode;
            window_stage_threshold <= gray_active_threshold;
            window_stage_x <= gray_active_x;
            window_stage_y <= gray_active_y;
            window_top_l2 <= {top_l2[3], top_l2[2], top_l2[1], top_l2[0]};
            window_top_l1 <= {top_l1[3], top_l1[2], top_l1[1], top_l1[0]};
            window_top_c <= {top_word[3], top_word[2], top_word[1], top_word[0]};
            window_mid_l2 <= {mid_l2[3], mid_l2[2], mid_l2[1], mid_l2[0]};
            window_mid_l1 <= {mid_l1[3], mid_l1[2], mid_l1[1], mid_l1[0]};
            window_mid_c <= {mid_word[3], mid_word[2], mid_word[1], mid_word[0]};
            window_cur_l2 <= {cur_l2[3], cur_l2[2], cur_l2[1], cur_l2[0]};
            window_cur_l1 <= {cur_l1[3], cur_l1[2], cur_l1[1], cur_l1[0]};
            window_cur_c <= {gray_word[3], gray_word[2], gray_word[1], gray_word[0]};

            O_tvalid      <= sobel_stage_valid;
            O_tuser       <= sobel_stage_valid && sobel_stage_tuser;
            O_tlast       <= sobel_stage_valid && sobel_stage_tlast;
            O_tdata       <= selected_data;
            O_gray_tvalid <= sobel_stage_valid;
            O_gray_tuser  <= sobel_stage_valid && sobel_stage_tuser;
            O_gray_tlast  <= sobel_stage_valid && sobel_stage_tlast;
            O_gray_data   <= sobel_stage_gray_data;
            O_gray_mode   <= sobel_stage_mode;

            if (gray_stage_valid) begin
                if (gray_stage_tuser) begin
                    frame_algo_mode <= gray_stage_mode;
                    frame_threshold <= gray_stage_threshold;
                end

                gray_line_a[gray_active_x]  <= {gray_word[3], gray_word[2], gray_word[1], gray_word[0]};
                if (gray_active_y != 0) begin
                    gray_line_b[gray_active_x] <= gray_line_a[gray_active_x];
                end

                gray_prev_word      <= {gray_word[3], gray_word[2], gray_word[1], gray_word[0]};
                gray_top_prev_word  <= (gray_active_y < 2) ? 32'd0 : gray_line_b[gray_active_x];
                gray_mid_prev_word  <= (gray_active_y == 0) ? 32'd0 : gray_line_a[gray_active_x];

                if (gray_stage_tlast) begin
                    x_group <= 8'd0;
                    y_pos   <= (gray_active_y == IMG_HEIGHT - 1) ? 10'd0 : gray_active_y + 10'd1;
                    gray_prev_word      <= 32'd0;
                    gray_top_prev_word  <= 32'd0;
                    gray_mid_prev_word  <= 32'd0;
                end
                else begin
                    x_group <= gray_active_x + 8'd1;
                end
            end

            sobel_stage_valid <= window_stage_valid;
            sobel_stage_tuser <= window_stage_valid && window_stage_tuser;
            sobel_stage_tlast <= window_stage_valid && window_stage_tlast;
            sobel_stage_rgb_data <= window_stage_rgb_data;
            sobel_stage_gray_data <= window_stage_gray_data;
            sobel_stage_word <= sobel_word;
            sobel_stage_mode <= window_stage_mode;
            sobel_stage_x <= window_stage_x;
            sobel_stage_y <= window_stage_y;

            if (sobel_stage_valid) begin
                sobel_line_a[morph_active_x] <= sobel_stage_word;
                if (morph_active_y != 0)
                    sobel_line_b[morph_active_x] <= sobel_line_a[morph_active_x];

                sobel_prev_word <= sobel_stage_word;
                sobel_top_prev_word <= (morph_active_y < 2) ? 4'd0 : sobel_line_b[morph_active_x];
                sobel_mid_prev_word <= (morph_active_y == 0) ? 4'd0 : sobel_line_a[morph_active_x];

                if (sobel_stage_tlast) begin
                    sobel_prev_word <= 4'd0;
                    sobel_top_prev_word <= 4'd0;
                    sobel_mid_prev_word <= 4'd0;
                end
            end
        end
    end

endmodule
