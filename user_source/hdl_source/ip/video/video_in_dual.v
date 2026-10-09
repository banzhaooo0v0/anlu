`timescale 1ns / 1ps

// Two image FIFOs share fixed 240-word DDR bursts. Frame-start inputs must
// be early blanking markers: allow the stretched reset and FIFO recovery
// to complete before either valid stream starts (at least 32 camera clocks
// with the project's faster DDR clock). Both inputs mark the same frame.
module video_in_dual #(
    parameter [24:0] PROC_OFFSET = 25'd3500000
) (
    input wire I_rst_n,
    input wire I_camera_clk,
    input wire I_camera_frame_start,
    input wire I_camera_valid,
    input wire [127:0] I_camera_data,
    input wire I_original_frame_start,
    input wire I_original_valid,
    input wire [127:0] I_original_data,
    input wire I_mipi_rx_error,
    input wire I_ddr_clk,
    input wire I_display_pause,
    input wire I_video_out_rd_busy,
    output wire O_video_in_wr_busy,
    output reg [1:0] O_video_out_rp,
    output reg O_ddr_user_wr_en,
    output reg [24:0] O_ddr_user_addr,
    output wire [127:0] O_ddr_user_wr_data,
    input wire I_ddr_user_ready,
    output wire O_ddr_user_req
);
    localparam [24:0] IMAGE_BASE_ADDR_0 = 25'd0;
    localparam [24:0] IMAGE_BASE_ADDR_1 = 25'd7000000;
    localparam [24:0] IMAGE_BASE_ADDR_2 = 25'd14000000;
    localparam [24:0] IMAGE_BASE_ADDR_3 = 25'd21000000;

    reg camera_start_ext;
    reg [3:0] camera_start_cnt;
    reg camera_start_d1, camera_start_d2, camera_start_d3;
    wire frame_start = ~camera_start_d3 & camera_start_d2;
    wire fifo_rst = !I_rst_n || camera_start_d3;

    reg [1:0] video_in_wp;
    reg [1:0] wr_state;             // 0 idle, 1 original, 2 processed
    reg [9:0] burst_count;
    reg last_source;                // 0 original, 1 processed
    reg output_source;
    reg [24:0] raw_addr, proc_addr;

    wire [8:0] raw_fifo_num, proc_fifo_num;
    wire [127:0] raw_fifo_data, proc_fifo_data;
    wire raw_fifo_re = (wr_state == 2'd1) && I_ddr_user_ready && !fifo_rst && !frame_start;
    wire proc_fifo_re = (wr_state == 2'd2) && I_ddr_user_ready && !fifo_rst && !frame_start;
    wire raw_ready = (raw_fifo_num >= 9'd240);
    wire proc_ready = (proc_fifo_num >= 9'd240);
    wire choose_proc = proc_ready && (!last_source || !raw_ready);
    wire choose_raw = !choose_proc && raw_ready;
    wire start_burst = (wr_state == 2'd0) && !fifo_rst && !frame_start && !I_video_out_rd_busy &&
                       I_ddr_user_ready && (raw_ready || proc_ready);

    assign O_video_in_wr_busy = (wr_state != 2'd0) | O_ddr_user_wr_en;
    assign O_ddr_user_req = O_video_in_wr_busy | ((!fifo_rst) && (raw_ready || proc_ready));
    assign O_ddr_user_wr_data = output_source ? proc_fifo_data : raw_fifo_data;

    w128_d512_fifo U_raw_fifo (
        .rst(fifo_rst), .clkw(I_camera_clk), .we(I_original_valid),
        .di(I_original_data), .afull(), .full_flag(), .wrusedw(),
        .clkr(I_ddr_clk), .re(raw_fifo_re), .dout(raw_fifo_data),
        .rdusedw(raw_fifo_num), .valid(), .empty_flag(), .aempty()
    );

    w128_d512_fifo U_proc_fifo (
        .rst(fifo_rst), .clkw(I_camera_clk), .we(I_camera_valid),
        .di(I_camera_data), .afull(), .full_flag(), .wrusedw(),
        .clkr(I_ddr_clk), .re(proc_fifo_re), .dout(proc_fifo_data),
        .rdusedw(proc_fifo_num), .valid(), .empty_flag(), .aempty()
    );

    always @(posedge I_camera_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            camera_start_ext <= 1'b0;
            camera_start_cnt <= 4'd0;
        end else if (I_camera_frame_start || I_original_frame_start) begin
            camera_start_ext <= 1'b1;
            camera_start_cnt <= 4'd0;
        end else if (camera_start_ext && camera_start_cnt == 4'd7) begin
            camera_start_ext <= 1'b0;
        end else if (camera_start_ext) begin
            camera_start_cnt <= camera_start_cnt + 1'b1;
        end
    end

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            camera_start_d1 <= 1'b0;
            camera_start_d2 <= 1'b0;
            camera_start_d3 <= 1'b0;
        end else begin
            camera_start_d1 <= camera_start_ext;
            camera_start_d2 <= camera_start_d1;
            camera_start_d3 <= camera_start_d2;
        end
    end

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            video_in_wp <= 2'd0;
            O_video_out_rp <= 2'd0;
        end else if (!I_display_pause && frame_start && !I_mipi_rx_error) begin
            video_in_wp <= video_in_wp + 1'b1;
            case (video_in_wp)
                2'd0: O_video_out_rp <= 2'd2;
                2'd1: O_video_out_rp <= 2'd3;
                2'd2: O_video_out_rp <= 2'd0;
                default: O_video_out_rp <= 2'd1;
            endcase
        end
    end

    always @(posedge I_ddr_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            wr_state <= 2'd0;
            burst_count <= 10'd0;
            last_source <= 1'b1;
            output_source <= 1'b0;
            O_ddr_user_wr_en <= 1'b0;
            O_ddr_user_addr <= IMAGE_BASE_ADDR_0;
            raw_addr <= IMAGE_BASE_ADDR_0;
            proc_addr <= IMAGE_BASE_ADDR_0 + PROC_OFFSET;
        end else begin
            O_ddr_user_wr_en <= 1'b0;

            if (frame_start) begin
                // An errored frame reuses the preceding write slot.
                case (I_mipi_rx_error ? (video_in_wp - 2'd1) : video_in_wp)
                    2'd0: begin raw_addr <= IMAGE_BASE_ADDR_0; proc_addr <= IMAGE_BASE_ADDR_0 + PROC_OFFSET; end
                    2'd1: begin raw_addr <= IMAGE_BASE_ADDR_1; proc_addr <= IMAGE_BASE_ADDR_1 + PROC_OFFSET; end
                    2'd2: begin raw_addr <= IMAGE_BASE_ADDR_2; proc_addr <= IMAGE_BASE_ADDR_2 + PROC_OFFSET; end
                    default: begin raw_addr <= IMAGE_BASE_ADDR_3; proc_addr <= IMAGE_BASE_ADDR_3 + PROC_OFFSET; end
                endcase
            end

            if (fifo_rst || frame_start) begin
                wr_state <= 2'd0;
                burst_count <= 10'd0;
                last_source <= 1'b1;
            end else if (wr_state != 2'd0) begin
                if (I_ddr_user_ready) begin
                    O_ddr_user_wr_en <= 1'b1;
                    output_source <= (wr_state == 2'd2);
                    if (wr_state == 2'd2) begin
                        O_ddr_user_addr <= proc_addr;
                        proc_addr <= proc_addr + 25'd8;
                    end else begin
                        O_ddr_user_addr <= raw_addr;
                        raw_addr <= raw_addr + 25'd8;
                    end
                    if (burst_count == 10'd239) begin
                        wr_state <= 2'd0;
                        burst_count <= 10'd0;
                        last_source <= (wr_state == 2'd2);
                    end else begin
                        burst_count <= burst_count + 1'b1;
                    end
                end
            end else if (start_burst) begin
                if (choose_proc) wr_state <= 2'd2;
                else if (choose_raw) wr_state <= 2'd1;
                burst_count <= 10'd0;
            end
        end
    end
endmodule
