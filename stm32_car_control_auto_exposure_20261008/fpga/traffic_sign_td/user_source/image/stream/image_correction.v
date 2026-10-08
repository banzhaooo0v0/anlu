
module image_correction #(
    parameter DATA_WIDTH   = 40 // RAW10输入数据宽度。
)(
    // 全局时钟与复位
    input                          	  I_clk   			,
    input                          	  I_rst_n 			,

    // RAW10输入流
    input    [DATA_WIDTH - 1:0]       I_raw_data		,
    input                             I_raw_valid 		,     
    input                             I_raw_frame_start	,
    input                             I_raw_frame_end  	,
    // 四像素RAW10输出流
    output     [DATA_WIDTH - 1:0]     O_raw_tdata 		,
    output                            O_raw_tlast 		,
    output                            O_raw_tvalid		,
    output                            O_raw_tuser 		,
    input                             O_raw_tready
);

    // 输入数据和有效信号各延迟一拍，保证RAW数据与视频标志对齐。
    reg                        I_raw_tvalid_d;
    reg    [DATA_WIDTH - 1:0]  I_raw_tdata_r;
    // h_cnt统计当前行中的有效处理组，v_cnt统计当前帧的行号。
    reg    [14:0]              h_cnt,v_cnt;
    wire                       V_valid,H_valid;
    wire                       tuser;

//********************************************************************//
//*************************** Input Delay *****************************//
//********************************************************************//
// RAW数据、valid信号使用同一拍延迟，后续计数均基于延迟后的valid。
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n )begin
            I_raw_tvalid_d <= 0;
            I_raw_tdata_r  <= 0;
        end
        else begin
            I_raw_tvalid_d <= I_raw_valid;
            I_raw_tdata_r  <= I_raw_data;
        end
    end
    
    // 统计输入valid之间的空拍数量，用于识别一行结束。
    reg  [7:0] cnt;
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n )begin
            cnt <= 0;
        end
        else if(I_raw_valid)
            cnt <= 0;
        else if(!I_raw_valid)begin
            cnt <= cnt + 1;
        end
    end

    // 连续11个空拍后认为上一行结束。
    wire last = (cnt == 10);

//********************************************************************//
//*************************** Coordinate ******************************//
//********************************************************************//
// 帧开始时清零行号，检测到行结束后递增行号。
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_raw_frame_start)
            v_cnt <= 0;
        else if(last)
            v_cnt  <=  v_cnt + 1;
    end

    // 只输出1024x600图像有效区域内的数据。
    assign V_valid = (v_cnt >= 0) && (v_cnt <= 599);

    // 统计当前行内的有效处理组数量。
    always @(posedge I_clk or negedge I_rst_n) begin
        if(!I_rst_n || I_raw_frame_start) 
            h_cnt <= 0;
        else if(last)
            h_cnt <= 0;
        else if(I_raw_tvalid_d)
            h_cnt <=  h_cnt + 1;
    end
    assign H_valid = (h_cnt <= 255) && (h_cnt >= 0);
    
    // 行号和组号都为0且输入数据有效时产生帧开始标志。
    assign tuser = (h_cnt == 0) && (v_cnt == 0) && I_raw_tvalid_d;

//********************************************************************//
//***************************** Main Code ****************************//
//********************************************************************//
// 固定速率输出：保留官方ready端口，但当前路径不执行反压。
    assign O_raw_tdata  = V_valid && H_valid? I_raw_tdata_r:0;
    // Fixed-rate path: the retained ready port is intentionally unused.
    assign O_raw_tvalid = H_valid && V_valid && I_raw_tvalid_d;
    assign O_raw_tlast  = V_valid && (h_cnt == 255) && I_raw_tvalid_d;
    assign O_raw_tuser  = tuser;

//   cwc cwc_inst
// (
// .probe0  (I_raw_data			),
// .probe1  (I_raw_valid 		),
// .probe2  (I_raw_frame_start	),
// .probe3  (I_raw_frame_end  	),
// .probe4  (O_raw_tdata 		),
// .probe5  (O_raw_tlast 		),
// .probe6  (O_raw_tvalid		),
// .probe7  (O_raw_tuser 		),
// .probe8  (h_cnt 				),
// .probe9  (v_cnt 				),
// .probe10 (cnt 				),
// .clk	  (I_clk				)
// );


endmodule
