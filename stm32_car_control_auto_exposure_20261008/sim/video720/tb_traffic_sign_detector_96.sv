`timescale 1ns/1ps

module tb_traffic_sign_detector_96;
    localparam integer IMG_WIDTH  = 1280;
    localparam integer IMG_HEIGHT = 720;
    localparam integer GROUPS     = IMG_WIDTH / 4;

    reg clk;
    reg rst_n;
    reg tuser;
    reg tlast;
    reg tvalid;
    reg [95:0] tdata;
    wire busy;
    wire done;
    wire result_valid;
    wire [4:0] result_class;
    wire [7:0] result_ascii;
    wire frame_drop;
    integer errors;

    traffic_sign_detector_96 #(
        .IMG_WIDTH (IMG_WIDTH),
        .IMG_HEIGHT(IMG_HEIGHT)
    ) dut (
        .I_clk          (clk),
        .I_rst_n        (rst_n),
        .I_tuser        (tuser),
        .I_tlast        (tlast),
        .I_tvalid       (tvalid),
        .I_tdata        (tdata),
        .O_busy         (busy),
        .O_done         (done),
        .O_result_valid (result_valid),
        .O_result_class (result_class),
        .O_result_ascii (result_ascii),
        .O_frame_drop   (frame_drop)
    );

    always #5 clk = ~clk;

    task send_frame;
        input integer scene;
        integer y;
        integer group;
        integer lane;
        integer pixel_x;
        integer pixel_y;
        reg [7:0] red;
        reg [7:0] green;
        reg [7:0] blue;
        reg [95:0] word;
        begin
            for (y = 0; y < IMG_HEIGHT; y = y + 1) begin
                for (group = 0; group < GROUPS; group = group + 1) begin
                    word = 96'd0;
                    for (lane = 0; lane < 4; lane = lane + 1) begin
                        pixel_x = group * 4 + lane - 1100;
                        pixel_y = y - 680;
                        red = 8'd8;
                        green = 8'd8;
                        blue = 8'd8;
                        if ((scene == 1) || (scene == 2) || (scene == 5)) begin
                            red = 8'd20;
                            green = 8'd50;
                            blue = 8'd220;
                            if (scene == 5 && (pixel_x >= 0) && (pixel_x < 8) && (pixel_y >= 3) && (pixel_y < 7)) begin
                                red = 8'd20;
                                green = 8'd50;
                                blue = 8'd220;
                            end
                            else if ((pixel_x < 8) || (pixel_x >= 24) ||
                                     (pixel_y < 2) || (pixel_y >= 14)) begin
                                red = 8'd8;
                                green = 8'd8;
                                blue = 8'd8;
                            end
                            if (scene == 1) begin
                                if ((pixel_x >= 0) && (pixel_x <= 13) && (pixel_y >= 6) && (pixel_y <= 9)) begin
                                    red = 8'd240; green = 8'd240; blue = 8'd240;
                                end
                            end
                            else if (scene == 2) begin
                                if ((pixel_x >= 19) && (pixel_x < 32) && (pixel_y >= 6) && (pixel_y <= 9)) begin
                                    red = 8'd240; green = 8'd240; blue = 8'd240;
                                end
                            end
                        end
                        else if (scene == 3 && (pixel_x >= 8) && (pixel_x < 24) &&
                                 (pixel_y >= 2) && (pixel_y < 14)) begin
                            // 红色物体不应通过蓝色差分阈值。
                            red = 8'd220;
                            green = 8'd20;
                            blue = 8'd20;
                        end
                        else if (scene == 4 && (pixel_x >= 14) && (pixel_x < 18) &&
                                 (pixel_y >= 6) && (pixel_y < 10)) begin
                            // 小面积蓝色噪声，面积阈值应拒绝。
                            red = 8'd20;
                            green = 8'd50;
                            blue = 8'd220;
                        end
                        else if (scene == 6 && (pixel_x >= 2) && (pixel_x < 30) &&
                                 (pixel_y >= 6) && (pixel_y < 10)) begin
                            // 宽而扁的蓝色物体，长宽比过滤应拒绝。
                            red = 8'd20;
                            green = 8'd50;
                            blue = 8'd220;
                        end
                        case (lane)
                            0: word[23:0]  = {red, green, blue};
                            1: word[47:24] = {red, green, blue};
                            2: word[71:48] = {red, green, blue};
                            default: word[95:72] = {red, green, blue};
                        endcase
                    end
                    @(negedge clk);
                    tdata  = word;
                    tvalid = 1'b1;
                    tuser  = (y == 0) && (group == 0);
                    tlast  = (group == GROUPS - 1);
                    @(posedge clk);
                end
            end
            @(negedge clk);
            tvalid = 1'b0;
            tuser  = 1'b0;
            tlast  = 1'b0;
            // 检测器有输入级、颜色特征级和结果级；等待帧尾分类完成。
            @(posedge clk);
            @(negedge clk);
            @(posedge clk);
            @(negedge clk);
            @(posedge clk);
            @(negedge clk);
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        tuser = 1'b0;
        tlast = 1'b0;
        tvalid = 1'b0;
        tdata = 96'd0;
        errors = 0;
        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        // 首帧只建立 ROI，结果必须为 UNKNOWN。
        send_frame(1);
        if (result_class !== 5'd0 || result_ascii !== "?") begin
            $display("FAIL first frame class=%0d ascii=%c", result_class, result_ascii);
            errors = errors + 1;
        end

        if (!dut.track_valid || dut.track_x_min !== 1108 || dut.track_x_max !== 1123 || dut.track_y_min !== 682 || dut.track_y_max !== 693)
            $fatal(1,"ROI beyond x=1024/y=600 corrupted: x=%0d..%0d y=%0d..%0d",dut.track_x_min,dut.track_x_max,dut.track_y_min,dut.track_y_max);

        // 第二帧在上一帧 ROI 内提供左箭头白色区域。
        send_frame(1);
        if (result_class !== 5'd1 || result_ascii !== "L") begin
            $display("FAIL left frame class=%0d ascii=%c", result_class, result_ascii);
            errors = errors + 1;
        end

        // 右箭头、无牌、非蓝物体和小面积噪声。
        send_frame(2);
        if (result_class !== 5'd2 || result_ascii !== "R") begin
            $display("FAIL right frame class=%0d ascii=%c", result_class, result_ascii);
            errors = errors + 1;
        end
        send_frame(0);
        if (result_class !== 5'd0 || result_ascii !== "?") begin
            $display("FAIL blank frame class=%0d ascii=%c", result_class, result_ascii);
            errors = errors + 1;
        end
        send_frame(3);
        if (result_class !== 5'd0 || result_ascii !== "?") begin
            $display("FAIL non-blue frame class=%0d ascii=%c", result_class, result_ascii);
            errors = errors + 1;
        end
        send_frame(4);
        if (result_class !== 5'd0 || result_ascii !== "?") begin
            $display("FAIL small-noise frame class=%0d ascii=%c", result_class, result_ascii);
            errors = errors + 1;
        end
        send_frame(6);
        if (result_class !== 5'd0 || result_ascii !== "?") begin
            $display("FAIL non-round frame class=%0d ascii=%c", result_class, result_ascii);
            errors = errors + 1;
        end
        // 多候选帧：主候选仍应优先于小候选，下一帧重新验证左箭头。
        send_frame(5);
        if (result_class !== 5'd0 || result_ascii !== "?") begin
            $display("FAIL multi-candidate frame class=%0d ascii=%c", result_class, result_ascii);
            errors = errors + 1;
        end
        send_frame(1);
        if (result_class !== 5'd1 || result_ascii !== "L") begin
            $display("FAIL post-multi left frame class=%0d ascii=%c", result_class, result_ascii);
            errors = errors + 1;
        end

        if (frame_drop !== 1'b0) begin
            $display("FAIL unexpected frame drop");
            errors = errors + 1;
        end
        if (errors == 0)
            $display("PASS traffic sign detector");
        if (errors != 0) $fatal(1,"detector failures=%0d",errors);
        $finish;
    end
endmodule
