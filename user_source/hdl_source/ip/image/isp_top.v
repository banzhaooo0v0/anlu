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

    // AWB后的原图并行输出，供双帧缓存链路单独保存。
    output [127:0]  O_original_tdata,
    output          O_original_tlast,
    output          O_original_tuser,
    output          O_original_tvalid,

    // CNN状态仅在工程内部使用，不增加design_top_wrapper物理端口。
    output wire        O_cnn_busy,
    output wire        O_cnn_done,
    output wire        O_cnn_result_valid,
    output wire [4:0]  O_cnn_result_class,
    output wire [7:0]  O_cnn_result_ascii,
    output wire        O_cnn_result_toggle,
    output wire        O_cnn_frame_drop,

    // Lightweight blue sign / arrow detector.  The result is a frame-level
    // ASCII direction ("L", "R" or "?") for the car controller.
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
  wire         awb_process_tuser;
  reg          awb_frame_pending;

  // 轻量去雾级：仅在00模式（CNN/去雾）启用，其他模式保持原始RGB。
  // 该级保持固定速率，不引入反压。
  wire         dehaze_O_tlast;
  wire         dehaze_O_tuser;
  wire [95:0]  dehaze_O_tdata;
  wire         dehaze_O_tvalid;
  reg [1:0] mode_delay [0:10];
  integer mode_index;
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if (!I_rst_n) begin
          for (mode_index=0; mode_index<11; mode_index=mode_index+1)
              mode_delay[mode_index] <= 2'b11;
      end else begin
          mode_delay[0] <= I_algo_mode;
          for (mode_index=1; mode_index<11; mode_index=mode_index+1)
              mode_delay[mode_index] <= mode_delay[mode_index-1];
      end
  end

  // CNN采样器和核心的单时钟域握手信号。
  wire         cnn_start;
  wire         cnn_start_bank;
  wire         cnn_frame_ready;
  wire         cnn_busy;
  wire         cnn_done;
  wire         cnn_result_valid;
  wire [4:0]   cnn_result_class;
  wire [7:0]   cnn_result_ascii;
  wire         cnn_input_rd_bank;
  wire [11:0]  cnn_input_rd_addr;
  wire [7:0]   cnn_input_rd_data;
  reg          cnn_result_toggle;
  wire         cnn_frame_drop;

  // Traffic sign detector result, in the same CSI/video clock domain as the
  // existing CNN.  It runs continuously and is independent of display mode.
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

  wire         awb_original_tuser_128;
  wire         awb_original_tvalid_128;
  wire         awb_original_tlast_128;
  wire [127:0] awb_original_tdata_128;

  // 固定速率链路由顶层提供ready，当前工程不暂停视频流。
  assign awb_O_tready = O_tready;
  assign O_tdata  = awb_O_tdata_128;
  assign O_tlast  = awb_O_tlast_128;
  // DDR FIFO reset needs the early AWB blanking marker, not the packed
  // first-pixel marker. Use one common marker for both image buffers.
  assign O_tuser  = awb_O_tuser;
  assign O_tvalid = awb_O_tvalid_128   ;

  assign O_original_tdata  = awb_original_tdata_128;
  assign O_original_tlast  = awb_original_tlast_128;
  assign O_original_tuser  = awb_O_tuser;
  assign O_original_tvalid = awb_original_tvalid_128;

  assign O_cnn_busy          = cnn_busy;
  assign O_cnn_done          = cnn_done;
  assign O_cnn_result_valid  = cnn_result_valid;
  assign O_cnn_result_class  = cnn_result_class;
  assign O_cnn_result_ascii  = cnn_result_ascii;
  assign O_cnn_result_toggle  = cnn_result_toggle;
  assign O_cnn_frame_drop    = cnn_frame_drop;
  assign O_traffic_sign_busy          = traffic_sign_busy;
  assign O_traffic_sign_done          = traffic_sign_done;
  assign O_traffic_sign_result_valid  = traffic_sign_result_valid;
  assign O_traffic_sign_result_class  = traffic_sign_result_class;
  assign O_traffic_sign_result_ascii  = traffic_sign_result_ascii;
  assign O_traffic_sign_result_toggle = traffic_sign_result_toggle;
  assign O_traffic_sign_frame_drop    = traffic_sign_frame_drop;

  // AWB保留官方提前帧标记，但RGB数据有效可能延后。
  // 将标记保持到第一个有效AWB输出拍，再交给图像处理模块锁存配置。
  assign awb_process_tuser = awb_O_tvalid && (awb_O_tuser || awb_frame_pending);

  // 记录没有伴随有效数据的AWB帧标记。
  always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
      if(!I_rst_n)
          awb_frame_pending <= 1'b0;
      else if(awb_O_tuser && !awb_O_tvalid)
          awb_frame_pending <= 1'b1;
      else if(awb_O_tvalid)
          awb_frame_pending <= 1'b0;
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

// 本次迁移的实时算法：00轻量去雾/CNN、灰度、Sobel、腐蚀和膨胀。
// 模式在帧首拍锁存，处理模块不使用暂停式反压。
image_process_stream_96 #(
    .IMG_HEIGHT(IMG_HEIGHT),
    .IMG_WIDTH (IMG_WIDTH)
) u_image_process_stream_96 (
    .I_clk           (axi4s_video_aclk),
    .I_rst_n         (I_rst_n),
    .I_tuser         (dehaze_O_tuser),
    .I_tlast         (dehaze_O_tlast),
    .I_tvalid        (dehaze_O_tvalid),
    .I_tdata         (dehaze_O_tdata),
    .I_algo_mode     (mode_delay[10]),
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

// Frame-level blue sign and arrow direction result for the STM32 car link.
// The detector always consumes AWB RGB. Display mode and dehaze selection
// cannot change its color thresholds or interrupt its frame heartbeat.
traffic_sign_detector_96 #(
    .IMG_WIDTH (IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT)
) u_traffic_sign_detector_96 (
    .I_clk          (axi4s_video_aclk),
    .I_rst_n        (I_rst_n),
    .I_tuser        (awb_process_tuser),
    .I_tlast        (awb_O_tlast),
    .I_tvalid       (awb_O_tvalid),
    .I_tdata        (awb_O_tdata),
    .O_busy         (traffic_sign_busy),
    .O_done         (traffic_sign_done),
    .O_result_valid (traffic_sign_result_valid),
    .O_result_class (traffic_sign_result_class),
    .O_result_ascii (traffic_sign_result_ascii),
    .O_frame_drop   (traffic_sign_frame_drop)
);

// 3x3暗通道近似 + 分段透射率增益。00模式同时供CNN使用去雾后的灰度，
// 因此识别链路和HDMI预览看到的是同一帧数据。
dehaze_stream_96 #(
    .IMG_WIDTH (IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT),
    .ATMOSPHERIC_LIGHT(240),
    .OMEGA_Q8(218),
    .MIN_TRANSMISSION(64)
) u_dehaze_stream_96 (
    .I_clk    (axi4s_video_aclk),
    .I_rst_n  (I_rst_n),
    .I_tuser  (awb_process_tuser),
    .I_tlast  (awb_O_tlast),
    .I_tvalid (awb_O_tvalid),
    .I_tdata  (awb_O_tdata),
    .I_enable (I_algo_mode == 2'b00),
    .O_tuser  (dehaze_O_tuser),
    .O_tlast  (dehaze_O_tlast),
    .O_tvalid (dehaze_O_tvalid),
    .O_tdata  (dehaze_O_tdata)
);

// 灰度旁路进入CNN全画面采样器；双缓冲状态保证推理期间输入不被覆盖。
cnn_input_sampler_96 #(
    .IMG_WIDTH (IMG_WIDTH),
    .IMG_HEIGHT(IMG_HEIGHT),
    .CNN_SIZE  (64)
) u_cnn_input_sampler_96 (
    .I_clk                   (axi4s_video_aclk),
    .I_rst_n                 (I_rst_n),
    .I_tuser                 (process_O_gray_tuser),
    .I_tlast                 (process_O_gray_tlast),
    .I_tvalid                (process_O_gray_tvalid),
    .I_gray_data             (process_O_gray_data),
    .I_core_busy             (cnn_busy),
    .I_core_done             (cnn_done),
    .I_core_bank             (cnn_input_rd_bank),
    .O_core_start            (cnn_start),
    .O_core_input_bank       (cnn_start_bank),
    .O_core_input_frame_ready(cnn_frame_ready),
    .I_core_rd_bank          (cnn_input_rd_bank),
    .I_core_rd_addr          (cnn_input_rd_addr),
    .O_core_rd_data          (cnn_input_rd_data),
    .O_frame_drop            (cnn_frame_drop),
    .O_capture_active        ()
);

cnn_core u_cnn_core (
    .aclk              (axi4s_video_aclk),
    .aresetn           (I_rst_n),
    .start             (cnn_start),
    .input_frame_ready (cnn_frame_ready),
    .input_bank_select (cnn_start_bank),
    .input_rd_bank     (cnn_input_rd_bank),
    .input_rd_addr     (cnn_input_rd_addr),
    .input_rd_data     (cnn_input_rd_data),
    .busy              (cnn_busy),
    .done              (cnn_done),
    .result_valid      (cnn_result_valid),
    .result_class      (cnn_result_class),
    .result_ascii      (cnn_result_ascii)
);

// 结果数据在核心时钟域稳定保持，toggle用于通知HDMI时钟域捕获新结果。
always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n)
        cnn_result_toggle <= 1'b0;
    else if (cnn_done)
        cnn_result_toggle <= ~cnn_result_toggle;
end

always @(posedge axi4s_video_aclk or negedge I_rst_n) begin
    if (!I_rst_n)
        traffic_sign_result_toggle <= 1'b0;
    else if (traffic_sign_done)
        traffic_sign_result_toggle <= ~traffic_sign_result_toggle;
end

// 官方数据格式转换：四拍96位数据拼接为三拍128位数据。
// 帧首标记按官方协议提前输出，行结束由算法标记延迟对齐。
    data_96bit_to_128bit u_data_96bit_to_128bit(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
	
        .I_96b_frame_start  ( process_O_tuser   ),
        .I_96b_last         ( process_O_tlast   ),
        .I_96b_valid        ( process_O_tvalid  ),
		.I_96b_data         ( process_O_tdata    ),
	
        .O_128b_frame_start ( awb_O_tuser_128  	),
		.O_128b_last       ( awb_O_tlast_128    ),
		.O_128b_valid       ( awb_O_tvalid_128 	),
        .O_128b_data        ( awb_O_tdata_128  	)
    );

    // 同一AWB流再打包一份，独立保存原图；无反压，处理支路有固定流水线延迟。
    data_96bit_to_128bit u_data_96bit_to_128bit_original(
        .I_clk              ( axi4s_video_aclk  ),
        .I_rst_n            ( I_rst_n           ),
        .I_96b_frame_start  ( awb_process_tuser  ),
        .I_96b_last         ( awb_O_tlast        ),
        .I_96b_valid        ( awb_O_tvalid       ),
        .I_96b_data         ( awb_O_tdata        ),
        .O_128b_frame_start ( awb_original_tuser_128  ),
        .O_128b_last        ( awb_original_tlast_128   ),
        .O_128b_valid       ( awb_original_tvalid_128  ),
        .O_128b_data        ( awb_original_tdata_128   )
    );



//data96_128 u_data96_128 (
//    .I_tdata(awb_O_tdata),
//    .O_tdata(awb_O_tdata_128)
//);
	
endmodule
