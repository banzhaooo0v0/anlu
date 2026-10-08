`timescale 1ns / 1ps

// 路牌识别结果跨时钟域同步。保留 traffic_sign_* 接口名称，兼容既有 HDMI OSD 连接。
// 源域先保持ASCII结果，再翻转toggle；目标域检测toggle变化后捕获稳定数据。
module traffic_sign_result_cdc (
    input  wire       I_src_clk,
    input  wire       I_src_rst_n,
    input  wire       I_src_toggle,
    input  wire [7:0] I_src_ascii,
    input  wire       I_dst_clk,
    input  wire       I_dst_rst_n,
    output reg        O_dst_toggle,
    output reg [7:0]  O_dst_ascii,
    output reg        O_dst_valid
);

    reg [7:0] src_ascii_hold;
    reg       src_toggle_seen;
    reg       dst_toggle_sync1;
    reg       dst_toggle_sync2;
    reg       dst_toggle_seen;
    reg       dst_capture_pending;
    reg [7:0] dst_ascii_sync1;
    reg [7:0] dst_ascii_sync2;

    // 结果ASCII在下一次结果到来前保持不变，目标域只同步稳定总线。
    always @(posedge I_src_clk or negedge I_src_rst_n) begin
        if (!I_src_rst_n) begin
            src_ascii_hold <= "?";
            src_toggle_seen <= 1'b0;
        end
        else begin
            // 只在结果toggle变化时更新总线，保证目标域同步期间数据稳定。
            if (I_src_toggle != src_toggle_seen) begin
                src_ascii_hold <= I_src_ascii;
                src_toggle_seen <= I_src_toggle;
            end
        end
    end

    always @(posedge I_dst_clk or negedge I_dst_rst_n) begin
        if (!I_dst_rst_n) begin
            dst_toggle_sync1 <= 1'b0;
            dst_toggle_sync2 <= 1'b0;
            dst_toggle_seen  <= 1'b0;
            dst_capture_pending <= 1'b0;
            dst_ascii_sync1  <= "?";
            dst_ascii_sync2  <= "?";
            O_dst_toggle     <= 1'b0;
            O_dst_ascii      <= "?";
            O_dst_valid      <= 1'b0;
        end
        else begin
            dst_toggle_sync1 <= I_src_toggle;
            dst_toggle_sync2 <= dst_toggle_sync1;
            dst_ascii_sync1  <= src_ascii_hold;
            dst_ascii_sync2  <= dst_ascii_sync1;
            O_dst_valid      <= 1'b0;
            if (dst_capture_pending) begin
                // toggle变化后再等待一个目标时钟，确保同步后的ASCII总线已稳定。
                dst_capture_pending <= 1'b0;
                O_dst_toggle        <= dst_toggle_sync2;
                O_dst_ascii         <= dst_ascii_sync2;
                O_dst_valid         <= 1'b1;
            end
            else if (dst_toggle_sync2 != dst_toggle_seen) begin
                dst_toggle_seen <= dst_toggle_sync2;
                dst_capture_pending <= 1'b1;
            end
        end
    end

endmodule
