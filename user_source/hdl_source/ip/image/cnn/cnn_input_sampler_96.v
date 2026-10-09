`timescale 1ns / 1ps

//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//
// 模块说明：
// 1. 接收四像素灰度流，按 IMG_WIDTH/64 像素宽度分区累加。
// 2. 逐个摄像头源行累加64个采样点，行边界由参数确定。
// 3. 两块4Kx8输入RAM交替使用，采样和推理不会访问同一块RAM。
// 4. 视频链路没有反压接口；两块RAM均被占用时置位O_frame_drop并丢弃该帧，
//    不把新旧帧混合写入CNN输入。
//********************************************************************//
module cnn_input_sampler_96 #(
    parameter integer IMG_WIDTH  = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer CNN_SIZE   = 64
) (
    input  wire        I_clk,
    input  wire        I_rst_n,

    input  wire        I_tuser,
    input  wire        I_tlast,
    input  wire        I_tvalid,
    input  wire [31:0] I_gray_data,

    input  wire        I_core_busy,
    input  wire        I_core_done,
    input  wire        I_core_bank,
    output reg         O_core_start,
    output reg         O_core_input_bank,
    output wire        O_core_input_frame_ready,

    input  wire        I_core_rd_bank,
    input  wire [11:0] I_core_rd_addr,
    output wire [7:0]  O_core_rd_data,

    output reg         O_frame_drop,
    output wire        O_capture_active
);

    localparam [1:0] BANK_FREE    = 2'd0;
    localparam [1:0] BANK_CAPTURE = 2'd1;
    localparam [1:0] BANK_READY   = 2'd2;
    localparam [1:0] BANK_RUN     = 2'd3;

    localparam integer GROUP_WIDTH = IMG_WIDTH / 4;

    reg [1:0] bank0_state;
    reg [1:0] bank1_state;
    reg       capture_bank;
    reg       capture_accept;
    reg       capture_active;
    reg       frame_finish_pending;
    reg       frame_finish_bank;

    localparam integer X_BITS = $clog2(GROUP_WIDTH);
    localparam integer CELL_GROUPS = GROUP_WIDTH / CNN_SIZE;
    localparam integer CELL_WIDTH = IMG_WIDTH / CNN_SIZE;
    localparam integer ROWS_LOW = IMG_HEIGHT / CNN_SIZE;
    localparam integer ROWS_HIGH = (IMG_HEIGHT + CNN_SIZE - 1) / CNN_SIZE;
    localparam [17:0] RECIP_LOW = ((1 << 24) + CELL_WIDTH*ROWS_LOW - 1)/(CELL_WIDTH*ROWS_LOW);
    localparam [17:0] RECIP_HIGH = ((1 << 24) + CELL_WIDTH*ROWS_HIGH - 1)/(CELL_WIDTH*ROWS_HIGH);
    reg [X_BITS-1:0] src_x_group;
    reg [5:0] cnn_x;
    reg [$clog2(CELL_GROUPS)-1:0] cell_group;
    wire [$clog2(CELL_GROUPS)-1:0] active_cell_group = I_tuser ? 0 : cell_group;
    reg [9:0] src_y;
    reg [5:0] cnn_y;
    // At 720p each cell contains at most 240 pixels (maximum sum 61200).
    reg [15:0] column_sum [0:CNN_SIZE-1];

    reg        input0_we;
    reg        input1_we;
    reg [11:0] input_wr_addr;
    reg [7:0]  input_wr_data;
    reg        write_pending;
    reg        write_bank;
    reg [11:0] write_addr;
    reg [15:0] write_sum;
    reg        write_high_rows;
    wire [7:0] input0_rd_data;
    wire [7:0] input1_rd_data;

    // 帧首拍优先选择输入RAM 0；RAM 0被占用时选择RAM 1。
    wire start_bank0_free = !capture_active && (bank0_state == BANK_FREE);
    wire start_bank1_free = !capture_active && (bank1_state == BANK_FREE);
    wire start_accept     = start_bank0_free || start_bank1_free;
    wire start_bank       = start_bank0_free ? 1'b0 : 1'b1;
    wire active_bank      = I_tuser ? start_bank : capture_bank;
    wire active_accept    = I_tuser ? start_accept : capture_accept;

    // 当前灰度流拍的源坐标。tuser与第一个有效数据同拍时直接使用零坐标。
    wire [X_BITS-1:0] current_x_group = I_tuser ? 8'd0 : src_x_group;
    wire [9:0] current_y       = I_tuser ? 10'd0 : src_y;
    wire [5:0] current_cnn_y   = I_tuser ? 6'd0 : cnn_y;
    wire [5:0] current_cnn_x   = I_tuser ? 6'd0 : cnn_x;
    wire       current_cnn_row_last = current_y == F_cnn_y_end(current_cnn_y);
    wire [9:0] source_gray_sum = {2'd0, I_gray_data[7:0]} + {2'd0, I_gray_data[15:8]}
                                + {2'd0, I_gray_data[23:16]} + {2'd0, I_gray_data[31:24]};
    wire [15:0] source_gray_sum_ext = {6'd0, source_gray_sum};
    wire [15:0] previous_column_sum =
        ((current_y == 10'd0) && (active_cell_group == 0))
        ? 16'd0 : column_sum[current_cnn_x];
    wire [15:0] column_sum_next = previous_column_sum + source_gray_sum_ext;
    wire        cnn_cell_write = I_tvalid && active_accept &&
                                 (active_cell_group == CELL_GROUPS-1) &&
                                 current_cnn_row_last;

    // An accepted frame initializes every column on its first source row;
    // cell completion clears the sum before reuse. No array reset is needed.
    always @(posedge I_clk) begin
        if (I_tvalid && active_accept) begin
            if (cnn_cell_write) column_sum[current_cnn_x] <= 16'd0;
            else column_sum[current_cnn_x] <= column_sum_next;
        end
    end


    assign O_capture_active = capture_active;
    assign O_core_input_frame_ready = (bank0_state == BANK_READY) ||
                                       (bank1_state == BANK_READY);

    // 两块RAM都持续响应CNN读地址，最后一级按bank选择对应数据。
    cnn_input_bram u_cnn_input_bank0 (
        .clka  (I_clk),
        .wea   (input0_we),
        .addra (input_wr_addr),
        .dina  (input_wr_data),
        .clkb  (I_clk),
        .addrb (I_core_rd_addr),
        .doutb (input0_rd_data)
    );

    cnn_input_bram u_cnn_input_bank1 (
        .clka  (I_clk),
        .wea   (input1_we),
        .addra (input_wr_addr),
        .dina  (input_wr_data),
        .clkb  (I_clk),
        .addrb (I_core_rd_addr),
        .doutb (input1_rd_data)
    );

    assign O_core_rd_data = I_core_rd_bank ? input1_rd_data : input0_rd_data;

    // 写回端使用一级流水，把坐标和累加和与平均值计算路径隔开。
    always @(*) begin
        input0_we     = write_pending && (write_bank == 1'b0);
        input1_we     = write_pending && (write_bank == 1'b1);
        input_wr_addr = write_addr;
        input_wr_data = F_cnn_average(write_sum, write_high_rows);
    end

    // Constant reciprocal division, exact over 0..255*cell_area for
    // supported 1024x600 and 1280x720 geometries. No variable divider.
    function [7:0] F_cnn_average;
        input [15:0] I_sum;
        input I_high_rows;
        reg [36:0] product;
        begin
            product = I_sum * (I_high_rows ? RECIP_HIGH : RECIP_LOW);
            F_cnn_average = product >> 24;
        end
    endfunction
    function [9:0] F_cnn_y_end;
        input [5:0] I_cnn_y;
        begin
            F_cnn_y_end = (({1'b0,I_cnn_y} + 1) * IMG_HEIGHT / CNN_SIZE) - 1;
        end
    endfunction
    function [3:0] F_cnn_y_height;
        input [5:0] I_cnn_y;
        begin
            F_cnn_y_height = (({1'b0,I_cnn_y}+1)*IMG_HEIGHT/CNN_SIZE)
                          - (I_cnn_y*IMG_HEIGHT/CNN_SIZE);
        end
    endfunction
    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin cnn_x<=0; cell_group<=0; end
        else if (I_tvalid) begin
            if (I_tlast) begin cnn_x<=0; cell_group<=0; end
            else if (active_cell_group == CELL_GROUPS-1) begin
                cnn_x<=current_cnn_x+1'b1; cell_group<=0;
            end else begin
                cnn_x<=current_cnn_x; cell_group<=active_cell_group+1'b1;
            end
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            bank0_state          <= BANK_FREE;
            bank1_state          <= BANK_FREE;
            capture_bank         <= 1'b0;
            capture_accept       <= 1'b0;
            capture_active       <= 1'b0;
            frame_finish_pending <= 1'b0;
            frame_finish_bank    <= 1'b0;
            src_x_group          <= 8'd0;
            src_y                <= 10'd0;
            cnn_y                <= 6'd0;
            O_core_start         <= 1'b0;
            O_core_input_bank    <= 1'b0;
            O_frame_drop         <= 1'b0;
            write_pending        <= 1'b0;
            write_bank           <= 1'b0;
            write_addr           <= 12'd0;
            write_sum            <= 16'd0;
            write_high_rows       <= 1'b0;
        end
        else begin
            O_core_start <= 1'b0;

            // 每个CNN单元完成后进入写回流水；RAM在下一拍写入平均值。
            write_pending <= cnn_cell_write;
            if (cnn_cell_write) begin
                write_bank     <= active_bank;
                write_addr     <= {current_cnn_y, current_cnn_x};
                write_sum      <= column_sum_next;
                write_high_rows <= (F_cnn_y_height(current_cnn_y) == ROWS_HIGH);
            end

            // 推理完成后释放其输入RAM，供后续帧重新使用。
            if (I_core_done) begin
                if (I_core_bank == 1'b0)
                    bank0_state <= BANK_FREE;
                else
                    bank1_state <= BANK_FREE;
            end

            // 最后一行的最后一个CNN单元写入后的下一个时钟沿标记为READY。
            if (frame_finish_pending) begin
                if (frame_finish_bank == 1'b0)
                    bank0_state <= BANK_READY;
                else
                    bank1_state <= BANK_READY;
                frame_finish_pending <= 1'b0;
            end

            // 启动脉冲先保持一个完整周期，下一拍由核心和采样器同时确认。
            // 这样核心看到的start、ready和bank选择来自同一拍，避免丢失脉冲。
            if (O_core_start) begin
                if (O_core_input_bank == 1'b0)
                    bank0_state <= BANK_RUN;
                else
                    bank1_state <= BANK_RUN;
            end
            else if (!I_core_busy && (bank0_state == BANK_READY)) begin
                O_core_start      <= 1'b1;
                O_core_input_bank <= 1'b0;
            end
            else if (!I_core_busy && (bank1_state == BANK_READY)) begin
                O_core_start      <= 1'b1;
                O_core_input_bank <= 1'b1;
            end

            if (I_tvalid) begin
                // 帧首拍选择可用RAM；无可用RAM时整帧标记为丢弃。
                if (I_tuser) begin
                    capture_bank   <= start_bank;
                    capture_accept <= start_accept;
                    capture_active <= 1'b1;
                    src_x_group    <= 8'd0;
                    src_y          <= 10'd0;
                    cnn_y          <= 6'd0;
                    if (start_accept) begin
                        if (start_bank == 1'b0)
                            bank0_state <= BANK_CAPTURE;
                        else
                            bank1_state <= BANK_CAPTURE;
                    end
                    else begin
                        O_frame_drop <= 1'b1;
                    end
                end

                // 每个摄像头源行结束时更新纵向分区计数。
                if (I_tlast) begin
                    src_x_group <= 8'd0;
                    if (current_y == IMG_HEIGHT - 1) begin
                        src_y <= 10'd0;
                        cnn_y <= 6'd0;
                        capture_active <= 1'b0;
                        if (active_accept) begin
                            frame_finish_pending <= 1'b1;
                            frame_finish_bank    <= active_bank;
                        end
                    end
                    else begin
                        src_y <= current_y + 10'd1;
                        if (current_cnn_row_last)
                            cnn_y <= current_cnn_y + 6'd1;
                        capture_active <= 1'b1;
                    end
                end
                else begin
                    src_x_group <= current_x_group + 8'd1;
                    src_y       <= current_y;
                end

            end

            // 推理启动脉冲需覆盖到核心下一次采样的时钟沿。
            // O_core_start在本always中只保持一个时钟周期。
        end
    end

endmodule
