`timescale 1ns / 1ps

////////////////////////////////////English///////////////////////////////////////
// Company:         Anlu contest migration
// Engineer:        Codex
//
// Create Date:     2026/09/01 22:00:00
// Design Name:     data_96bit_to_128bit
// Module Name:     data_96bit_to_128bit
// Description:     Pack four 96-bit stream beats into three 128-bit beats and align line end.
// Simulations:     sim/tb_data96_128.sv (Icarus PASS)
//
// Referrences:     Official lab_hd_3_osd data path.
//
// Dependencies:    None
//
// Version:         V1.0
// Revision Date:   2026/09/01 22:00:00
// History:
// Time             Version     Revised by        Contents
// 2026/09/01       V1.0        Codex             Repair valid-gap and reset behavior.
///////////////////////////////////Chinese////////////////////////////////////////
// 版权归属:        安路赛题迁移工程
// 开发人员:        Codex
//
// 创建日期:        2026年09月01日
// 设计名称:        data_96bit_to_128bit
// 模块名称:        data_96bit_to_128bit
// 模块说明:        将4拍96位流数据打包为3拍128位流数据，并对齐行结束标记。
// 仿真工程:        sim/tb_data96_128.sv（Icarus 已通过）
// 参考资料:        官方lab_hd_3_osd数据链路。
// 依赖文件:        无
//
// 当前版本:        V1.0
// 修订日期:        2026年09月01日
// 修订历史:
// 时间             版本        修订人            修订内容
// 2026年09月01日   V1.0        Codex             修复复位和valid间隙处理。

module data_96bit_to_128bit (
	// 全局时钟与复位
	input wire         I_clk,
	input wire         I_rst_n,

	// 96位输入流：帧首标记只在首个有效拍使用。
	input wire         I_96b_frame_start,
	input wire         I_96b_last,
	input wire         I_96b_valid,
	input wire [95:0] I_96b_data,

	// 128位输出流：帧首标记沿用官方提前通知协议。
	output reg         O_128b_frame_start,
	output reg         O_128b_last,
	output reg         O_128b_valid,
	output reg [127:0] O_128b_data
);

	// 保存上一拍96位数据，用于跨拍拼接。
	reg [95:0] S_96b_data_1d;
	// 有效96位数据计数：0、1、2、3分别对应拼接阶段。
	reg [1:0]  S_cnt;


	// 帧首标记和上一拍数据寄存。帧首标记不要求伴随128位有效数据。
	always @(posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n) begin
			S_96b_data_1d       <= 96'd0;
			O_128b_frame_start <= 1'b0;
		end
		else begin
			if(I_96b_valid)
				S_96b_data_1d <= I_96b_data;
			O_128b_frame_start <= I_96b_frame_start;
		end
	end


	// 只对有效96位输入计数，输入空拍不会改变拼接位置。
	always @(posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n)
			S_cnt <= 2'd0;
		else if(I_96b_frame_start)
			S_cnt <= I_96b_valid ? 2'd1 : 2'd0;
		else if(I_96b_valid)
			S_cnt <= I_96b_last ? 2'd0 : S_cnt + 2'd1;
	end


	// 按四拍96位数据生成三拍128位数据：
	// A、B、C、D -> {A,B[95:64]}、{B[63:0],C[95:32]}、{C[31:0],D}。
	always @(posedge I_clk or negedge I_rst_n) begin
		if(!I_rst_n) begin
			O_128b_valid <= 1'b0;
			O_128b_data  <= 128'd0;
			O_128b_last  <= 1'b0;
		end
		else if(I_96b_frame_start) begin
			O_128b_valid <= 1'b0;
			O_128b_data  <= 128'd0;
			O_128b_last  <= 1'b0;
		end
			else if(I_96b_valid)
				begin
					case(S_cnt)
						2'd0 :
							begin
								// 第一拍只缓存，不足128位不能输出。
								O_128b_valid <= 1'b0;
							O_128b_data  <= 128'd0;
							O_128b_last  <= 1'b0;
						end
						2'd1 :
							begin
								// 第二拍拼出第一个128位输出。
								O_128b_valid <= 1'b1;
							O_128b_data  <= {S_96b_data_1d,I_96b_data[95:64]};
								O_128b_last  <= 1'b0;
						end
						2'd2 :
							begin
								// 第三拍拼出第二个128位输出。
								O_128b_valid <= 1'b1;
							O_128b_data  <= {S_96b_data_1d[63:0],I_96b_data[95:32]};
								O_128b_last  <= 1'b0;
						end
						2'd3 :
							begin
								// 第四拍拼出第三个128位输出并回到下一组。
								O_128b_valid <= 1'b1;
							O_128b_data  <= {S_96b_data_1d[31:0],I_96b_data};
								O_128b_last  <= I_96b_last;
						end
					default:
						begin
							O_128b_valid <= 1'b0;
							O_128b_data  <= 128'd0;
							O_128b_last  <= 1'b0;
						end
				endcase
			end
		else
			begin
				O_128b_valid <= 1'b0;
				O_128b_data  <= 128'd0;
				O_128b_last  <= 1'b0;
			end
	end



endmodule
