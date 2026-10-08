module isp_top #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter [10:0] EDGE_THRESHOLD = 11'd24 // Sobel边缘阈值，帧内保持不变。
) (
    // 全局时钟与复位
    input 			axi4s_video_aclk,
    input 			I_rst_n			,

    // 输入RAW视频流
    input 			I_tlast			,
    input 			I_tuser			,
    input [39:0] 	I_tdata			,
    input 			I_tvalid		,
    input [9:0] 	I_tdest			,

    // 图像处理配置和输出握手
    input [1:0]  	I_algo_mode		,
    input 			O_tready		,

    // 输出RGB视频流
    output [127:0] 	O_tdata			,
    output 			O_tlast			,
    output 			O_tuser			,
    output 			O_tvalid		,
    output 			I_tready,

    // 路牌识别状态仅在工程内部使用，不增加design_top_wrapper物理端口。
    output wire        O_traffic_sign_busy,
    output wire        O_traffic_sign_done,
    output wire        O_traffic_sign_result_valid,
    output wire [4:0]  O_traffic_sign_result_class,
    output wire [7:0]  O_traffic_sign_result_ascii,
    output wire        O_traffic_sign_result_toggle,
    output wire        O_traffic_sign_frame_drop
);
 
//********************************************************************//
//****************** Parameter and Internal Signal *******************//
//********************************************************************//
// demosaic输出的128位四像素流及其握手信号。
wire         m_aixs_tvalid;  //synthesis keep 
  wire [127:0] m_aixs_tdata;  //synthesis keep 
  wire         m_aixs_tuser;  //synthesis keep 
  wire         m_aixs_tlast;  //synthesis keep 
  wire         m_aixs_tready;  //synthesis keep 
  
  // 128位输入流拆成96位四个RGB888像素。
  wire [ 95:0] m_aixs_tdata_96;  //synthesis keep 


  // AWB输出流。
  wire         awb_O_tlast;  //synthesis keep 
  wire         awb_O_tuser;  //synthesis keep 
  wire [ 95:0] awb_O_tdata;  //synthesis keep 
  wire         awb_O_tvalid;  //synthesis keep 
  wire         awb_O_tready;  //synthesis keep 

  // 图像算法输出流。
  wire         process_O_tlast;
  wire         process_O_tuser;
  wire [95:0]  process_O_tdata;
  wire         process_O_tvalid;
  wire         process_O_gray_tuser;
  wire         process_O_gray_tlast;
  wire         process_O_gray_tvalid;
  wire [31:0]  process_O_gray_data;
  wire [1:0]   process_O_gray_mode;
  // AWB帧首标记可能早于有效数据，pending用于等待首个有效拍。
  wire         process_I_tuser;
  reg          awb_frame_pending;

  // AWB到实时算法之间的寄存器切分。它隔离AWB乘法链和图像算法的
  // 灰度/Sobel组合逻辑，同时保持数据、行尾、帧首和模式同拍对齐。
  reg          process_stage_tvalid;
  reg          process_stage_tuser;
  reg          process_stage_tlast;
  reg  [95:0]  process_stage_tdata;
  reg  [1:0]   process_stage_algo_mode;

  // 传统蓝底白箭头识别器的帧级结果握手信号。
  // 保留 traffic_sign_* 内部别名，避免改变 design_top_wrapper 和 HDMI OSD 端口。
  wire         traffic_sign_busy;
  wire         traffic_sign_done;
  wire         traffic_sign_result_valid;
  wire [4:0]   traffic_sign_result_class;
  wire [7:0]   traffic_sign_result_ascii;
  reg          traffic_sign_result_toggle;
  wire         traffic_sign_frame_drop;

  // 打包器输出的官方视频流标志和数据。
  wire         awb_O_tuser_128;  //synthesis keep 
  wire         awb_O_tvalid_128;  //synthesis keep 
  wire         awb_O_tlast_128;  //synthesis keep 
  wire [127:0] awb_O_tdata_128;  //synthesis keep 

  // 固定速率链路由顶层提供ready，当前工程不暂停视频流。
  assign awb_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = awb_O_tlast_128;
  assign O_tuser  = awb_O_tuser_128    ;
  assign O_tvalid = awb_O_tvalid_128   ;

  assign O_traffic_sign_busy          = traffic_sign_busy;
  assign O_traffic_sign_done          = traffic_sign_done;
  assign O_traffic_sign_result_valid  = traffic_sign_result_valid;
  assign O_traffic_sign_result_class  = traffic_sign_result_class;
  assign O_traffic_sign_result_ascii  = traffic_sign_result_ascii;
  assign O_traffic_sign_result_toggle  = traffic_sign_result_toggle;
  assign O_traffic_sign_frame_drop    = traffic_sign_frame_drop;

  // AWB保留官方提前帧标记，但RGB数据有效可能延后。
  // 将标记保持到第一个有效AWB输出拍，再交给图像处理模块锁存配置。
  assign process_I_tuser = awb_O_tvalid && (awb_O_tuser || awb_frame_pending);

  // 记录没有伴随有效数据的AWB帧标记。
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if(!I_rst_n)
          awb_frame_pending <= 1'b0;
      else if(awb_O_tuser && !awb_O_tvalid)
          awb_frame_pending <= 1'b1;
      else if(awb_O_tvalid)
          awb_frame_pending <= 1'b0;
  end

  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          process_stage_tvalid    <= 1'b0;
          process_stage_tuser     <= 1'b0;
          process_stage_tlast     <= 1'b0;
          process_stage_tdata     <= 96'd0;
          process_stage_algo_mode <= 2'b11;
      end
      else begin
          process_stage_tvalid    <= awb_O_tvalid;
          process_stage_tuser     <= process_I_tuser;
          process_stage_tlast     <= awb_O_tlast;
          process_stage_tdata     <= awb_O_tdata;
          process_stage_algo_mode <= I_algo_mode;
      end
  end
  
  //assign m_aixs_tready = O_tready;
  //assign O_tdata  = m_aixs_tdata;
  //assign O_tlast  = m_aixs_tlast    ;
  //assign O_tuser  = m_aixs_tuser    ;
  //assign O_tvalid = m_aixs_tvalid   ;
 
 
//********************************************************************//
//***************************** ISP Pipeline *************************//
//********************************************************************//
// RAW10两路MIPI数据经过demosaic后形成四像素RGB流。
demosaic #(
    .IMG_HEIGHT          (IMG_HEIGHT),  // 图像高度
    .IMG_WIDTH           (IMG_WIDTH),   // 图像宽度
    .data_complete_delay (50  ),
    .BAYER_MODE          ("BGGR")
)
u_demosaic
(
    .I_clk   			(axi4s_video_aclk)	,   // 时钟信号
    .I_rst_n 			(I_rst_n)	,   // 复位信号，低有效
    .axi4s_video_tdata 	(I_tdata)	,  // AXI4-Stream视频数据
    .axi4s_video_tdest 	(I_tdest)	,
    .axi4s_video_tlast 	(I_tlast)	,  // 行结束信号
    .axi4s_video_tvalid	(I_tvalid)	,  // 数据有效信号
    .axi4s_video_tuser 	(I_tuser)	,  // 帧开始信号
    .axi4s_video_tready	(I_tready)	,  // 从模块准备好接受数据
    .O_tlast  			(m_aixs_tlast)	,  // 输出行结束信号
    .O_tuser  			(m_aixs_tuser)	,  // 输出帧开始信号
    .O_tdata  			(m_aixs_tdata)	,  // 输出数据
    .O_tvalid 			(m_aixs_tvalid)	,  // 输出数据有效信号
    .O_tready   		(m_aixs_tready)	   // 输出数据准备好信号
);
 
// 官方数据格式转换：128位四像素数据转为96位RGB888数据。
data128_96 u_data128_96 (
    .I_tdata(m_aixs_tdata),
    .O_tdata(m_aixs_tdata_96)
);

// 自动白平衡，保持官方AWB输出时序。
awb #(
    .IMG_HEIGHT(IMG_HEIGHT),
    .IMG_WIDTH (IMG_WIDTH)
) u_awb (
    .I_clk   (axi4s_video_aclk),
    .I_rst_n (I_rst_n),
    .I_tlast (m_aixs_tlast),
    .I_tuser (m_aixs_tuser),
    .I_tdata (m_aixs_tdata_96),
    .I_tvalid(m_aixs_tvalid),
    .I_tready(m_aixs_tready),
    .O_tlast (awb_O_tlast ),
    .O_tuser (awb_O_tuser ),
    .O_tdata (awb_O_tdata ),
    .O_tvalid(awb_O_tvalid),
    .O_tready(awb_O_tready)
);

// 本次迁移的实时算法：灰度、Sobel、腐蚀和膨胀。
// 模式在帧首拍锁存，处理模块不使用暂停式反压。
image_process_stream_96 #(
    .IMG_HEIGHT(IMG_HEIGHT),
    .IMG_WIDTH (IMG_WIDTH)
) u_image_process_stream_96 (
    .I_clk           (axi4s_video_aclk),
    .I_rst_n         (I_rst_n),
    .I_tuser         (process_stage_tuser),
    .I_tlast         (process_stage_tlast),
    .I_tvalid        (process_stage_tvalid),
    .I_tdata         (process_stage_tdata),
    .I_algo_mode     (process_stage_algo_mode),
    .I_edge_threshold(EDGE_THRESHOLD),
    .O_tuser         (process_O_tuser),
    .O_tlast         (process_O_tlast),
    .O_tvalid        (process_O_tvalid),
    .O_tdata         (process_O_tdata),
    .O_gray_tuser    (process_O_gray_tuser),
    .O_gray_tlast    (process_O_gray_tlast),
    .O_gray_tvalid   (process_O_gray_tvalid),
    .O_gray_data     (process_O_gray_data),
    .O_gray_mode     (process_O_gray_mode)
);

// 传统 FPGA 路牌识别：蓝色分割、形态学、连通域和下一帧箭头投票。
traffic_sign_detector_96 #(
    .IMG_WIDTH (IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT)
) u_traffic_sign_detector_96 (
    .I_clk          (axi4s_video_aclk),
    .I_rst_n        (I_rst_n),
    .I_tuser        (process_stage_tuser),
    .I_tlast        (process_stage_tlast),
    .I_tvalid       (process_stage_tvalid),
    .I_tdata        (process_stage_tdata),
    .O_busy         (traffic_sign_busy),
    .O_done         (traffic_sign_done),
    .O_result_valid (traffic_sign_result_valid),
    .O_result_class (traffic_sign_result_class),
    .O_result_ascii (traffic_sign_result_ascii),
    .O_frame_drop   (traffic_sign_frame_drop)
);

// 结果数据在核心时钟域稳定保持，toggle用于通知HDMI时钟域捕获新结果。
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n)
        traffic_sign_result_toggle <= 1'b0;
    else if (traffic_sign_done)
        traffic_sign_result_toggle <= ~traffic_sign_result_toggle;
end

// 官方数据格式转换：四拍96位数据拼接为三拍128位数据。
// Video input clears its asynchronous FIFO for several clocks on frame_start.
// Forward AWB's early frame marker, as in the official example, so the reset
// completes before the first packed pixel reaches the FIFO. The processed
// tuser is aligned with the first valid pixel and is too late for that reset.
    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( awb_O_tuser       ),
        .I_96b_last         ( process_O_tlast   ),
        .I_96b_valid        ( process_O_tvalid  ),
		.I_96b_data         ( process_O_tdata    ),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
		.O_128b_last       ( awb_O_tlast_128    ),
		.O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule
