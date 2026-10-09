`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlu contest migration
// Engineer:        Codex
//
// Create Date:     2026/09/01 22:00:00
// Design Name:     mode_selector
// Module Name:     mode_selector
// Description:     Synchronize and debounce two active-low image-mode buttons.
// Simulations:     sim/tb_mode_selector.sv (Icarus PASS)
// Referrences:     Project profile and lab_hd_3_osd button interface.
// Dependencies:    None
// Version:         V1.0
// Revision Date:   2026/09/01 22:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/09/01       V1.0        Codex             Create button mode selector.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路赛题迁移工程
// 开发人员:        Codex
// 创建日期:        2026年09月01日
// 设计名称:        mode_selector
// 模块名称:        mode_selector
// 模块说明:        同步并去抖两个低有效图像模式按键。
// 仿真工程:        sim/tb_mode_selector.sv（Icarus 已通过）
// 参考资料:        项目画像和lab_hd_3_osd按键接口。
// 依赖文件:        无
// 当前版本:        V1.0
// 修订日期:        2026年09月01日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年09月01日   V1.0        Codex             创建按键模式选择器。

module mode_selector #(
	parameter integer DEBOUNCE_CYCLES = 100000, // 24 MHz下约4.17 ms。
	parameter integer SHORT_PRESS_LIMIT = 12000000 // 约0.5 s；长按KEY4仍为小车限速。
) (
	// 全局时钟与复位
	input  wire       I_clk,
	input  wire       I_rst_n,

	// 两路原有扩展口输入，保留旧版外接按钮/跳线的模式选择。
	input  wire [1:0] I_button,
	// 板载KEY4（低有效）短按循环画面，长按仍由小车控制模块限速。
	input  wire       I_cycle_button_n,

	// 当前帧算法模式
	output reg  [1:0] O_mode
);

	// 按键同步寄存器，消除按键输入与系统时钟之间的亚稳态风险。
	reg [1:0] button_sync_1;
	reg [1:0] button_sync_2;
	// candidate_mode为去抖候选值，stable_count统计其连续稳定时间。
	reg [1:0] candidate_mode;
	reg [16:0] stable_count;
	reg [1:0] external_mode;
	reg [1:0] board_mode;
	reg key_sync_1, key_sync_2, key_stable, key_stable_d;
	reg [16:0] key_debounce_count;
	reg [23:0] hold_count;

	// 模式编码：11原图、10腐蚀、01膨胀、00路牌识别。
	wire [1:0] sampled_mode;

	assign sampled_mode = button_sync_2;

	// 两级同步、候选值检测和稳定计数均在同一时钟域完成。
	always @(posedge I_clk or negedge I_rst_n) begin
		if (!I_rst_n) begin
			// 复位时按键默认为释放状态，输出原图模式。
			button_sync_1 <= 2'b11;
			button_sync_2 <= 2'b11;
			candidate_mode <= 2'b11;
			stable_count <= 17'd0;
			external_mode <= 2'b11;
			board_mode <= 2'b11;
			key_sync_1 <= 1'b1;
			key_sync_2 <= 1'b1;
			key_stable <= 1'b1;
			key_stable_d <= 1'b1;
			key_debounce_count <= 17'd0;
			hold_count <= 24'd0;
			O_mode <= 2'b11;
		end
		else begin
			// 先同步外部按键，再使用同步后的值参与去抖。
			button_sync_1 <= I_button;
			button_sync_2 <= button_sync_1;

			if (sampled_mode != candidate_mode) begin
				// 按键状态发生变化，重新开始稳定计数。
				candidate_mode <= sampled_mode;
				stable_count <= 17'd0;
			end
			else if (stable_count < DEBOUNCE_CYCLES - 1) begin
				// 候选模式保持不变，继续累计去抖周期。
				stable_count <= stable_count + 17'd1;
			end
			else begin
				// 候选模式稳定达到设定周期后更新输出。
				external_mode <= candidate_mode;
			end

			key_sync_1 <= I_cycle_button_n;
			key_sync_2 <= key_sync_1;
			key_stable_d <= key_stable;
			if (key_sync_2 == key_stable)
				key_debounce_count <= 17'd0;
			else if (key_debounce_count == DEBOUNCE_CYCLES - 1) begin
				key_stable <= key_sync_2;
				key_debounce_count <= 17'd0;
			end
			else
				key_debounce_count <= key_debounce_count + 17'd1;

			if (!key_stable) begin
				if (hold_count < SHORT_PRESS_LIMIT)
					hold_count <= hold_count + 24'd1;
			end
			else begin
				// 仅短按释放时换模式；长按只保留原有小车限速作用。
				if (!key_stable_d && hold_count < SHORT_PRESS_LIMIT &&
				    external_mode == 2'b11) begin
					case (board_mode)
						2'b11: board_mode <= 2'b10;
						2'b10: board_mode <= 2'b01;
						2'b01: board_mode <= 2'b00;
						default: board_mode <= 2'b11;
					endcase
				end
				hold_count <= 24'd0;
			end

			O_mode <= (external_mode == 2'b11) ? board_mode : external_mode;
		end
	end

endmodule
