# 安路 PH1P35 迁移工程 IP 来源记录

日期：2026年09月02日

2026-10-08 补充：为适配原图/处理图双缓存，`ip/image/signal_delay.v` 直接参数化已有 `ram_f84573da5ab5` 包装器，将 AWB 延迟 RAM 深度从固定 2048 改为 `IMG_WIDTH/4`。未修改 `user_source/ip_source` 中的该厂商包装器或 RAM 原语定义。`sim/models/awb_ram_behavioral.v` 只用于地址/容量等价性检查，不参与综合，也不代表厂商原语时序。

## 结论

目标工程中的厂商 IP 和官方生成文件来自安路官方 `lab_hd_3_osd` 例程，不是临时创建，也不是从 `D:/la32r_soc` 复制。哈希核对在目标工程重排目录后完成。

官方例程根目录：

`D:/anlu/HX1P35A_Contest_202606/7_lab_ex_2026_nosoft/lab_hd_3_osd`

目标工程根目录：

`D:/anlu/rtl`

## 逐文件核对结果

| 内容 | 目标目录 | 官方对应目录 | 结果 |
|---|---|---|---|
| 官方生成 IP 包 | `user_source/ip_source` | `user_source/ip_source` | 53/53 文件一致 |
| demosaic 厂商目录 | `user_source/hdl_source/ip/image/demosaic_4x_2_0` | `user_source/hdl_source/isp/demosaic_4x_2_0` | 24/24 文件一致 |
| DDR2 厂商目录 | `user_source/hdl_source/ip/memory/ph1p35_ddr` | `user_source/hdl_source/ph1p35_ddr` | 54/54 文件一致 |
| MIPI D-PHY 目录 | `user_source/hdl_source/ip/camera/mipi/mipi_dphy_rx` | `user_source/hdl_source/mipi_dphy_rx` | 7/7 文件一致 |
| UICS500 配置目录 | `user_source/hdl_source/ip/camera/config/uics500_cfg` | `user_source/hdl_source/uics500_cfg` | 5/5 文件一致 |
| UIISP 配置目录 | `user_source/hdl_source/ip/camera/config/uiisp_beta` | `user_source/hdl_source/uiisp_beta` | 3/3 文件一致 |

核对规则：相对路径相同的文件比较 SHA-256；目录之间同时检查缺失、额外和内容变化文件。以上六项均为 `missing=0`、`extra=0`、`changed=0`。

## 当前 `.al` 的 IP 相关引用

`camera_to_dsi_display.al` 共包含 56 个源文件条目。直接匹配到 IP 配置或厂商 IP 目录的条目如下：

- `user_source/ip_source/PLL/PLL.xml`
- `user_source/ip_source/w128_d512_fifo/w128_d512_fifo.xml`
- `user_source/ip_source/w155_d512_fifo/w155_d512_fifo.xml`
- `user_source/ip_source/blk_mem_gen_awb_delay_signal/blk_mem_gen_awb_delay_signal.xml`
- `user_source/ip_source/divider/divider.ipc`
- `user_source/hdl_source/ip/memory/ph1p35_ddr/ddr2/ddr2.xml`
- `user_source/hdl_source/ip/image/demosaic_4x_2_0/blk_mem_gen_zhenghe/blk_mem_gen_zhenghe.xml`
- `user_source/hdl_source/ip/image/demosaic_4x_2_0/blk_mem_gen_demosaic/blk_mem_gen_demosaic.xml`
- DDR2 wrapper 和 demosaic 的官方 RTL 文件。

`MCU` 和 `w40_d512_fifo` 位于官方 `ip_source` 副本中，但当前 `.al` 没有直接列出它们的 XML。保留它们是为了保持官方 IP 包完整，不代表新增了使用关系。

工程中仍然存在官方视频链路使用的 `uial2axis.v` 等 AXI4-Stream 接口。它们服务于摄像头到 ISP 的视频流，不是原 `img_accel` 的 CPU AXI 或 DMA 控制依赖。

## 本次新增 RTL 的 IP 边界

`user_source/hdl_source/ip/image/image_process_stream_96.v` 是本次新增的算法 RTL。它不例化厂商 IP，四组行缓存由 Verilog 数组推断。TD 独立 `check_rtl` 结果为 4 个 RAM 推断，未出现 IP 实例错误。

`user_source/hdl_source/ip/image/dehaze_stream_96.v` 是成员二新增的轻量去雾 RTL。它使用两组 8 位组级暗通道行缓存，TD 独立分析结果为 2 个 RAM 推断；透射率采用分段移位增益，没有除法器或整帧缓存。

`user_source/hdl_source/ip/video/video_in_dual.v` 只复用已有 `w128_d512_fifo`，为原图和处理图各保留一条异步 FIFO，按突发交替写入 DDR 的同一帧槽不同地址区，无新增厂商 IP。

`D:/la32r_soc/rtl/ip/image/img_accel.v` 和 `img_accel_calc.v` 只用于确认算法公式和窗口行为。原工程的 CPU AXI、DMA、静态整帧 BRAM、CNN 和 Xilinx IP 均未加入安路目标工程。
