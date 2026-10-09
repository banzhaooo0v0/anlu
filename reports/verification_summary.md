# 安路 PH1P35 验证报告索引

当前整合日期：**2026-10-09**，目标 **1280×720**。本次接入方向识别、STM32 小车控制、逐像素形态学以及配套 720p 摄像头/曝光/显示配置。

最新结果以 [本次整合验证报告](integration_20261009.md) 为准。下列历史数据及 [10 月 8 日 TD 修复报告](td_fix_20261008.md) 对应旧的 1024×600 工程，不是当前源码或 bitstream 的通过证据。

当前结果：15 项功能仿真及去雾/AWB/双图 DDR 回归通过；TD 最终布线 SWNS +0.115 ns、HWNS +0.020 ns、TNS 均为 0；已生成 [720p 未压缩 bitstream](../release/720p_20261009/camera_to_dsi_display_720p.bit)。单线程布线、关闭 bitstream 压缩的恢复过程及剩余硬件验证边界均记录在本次报告中。

## 历史迁移记录（2026年09月02日）

## 交付范围

目标工程位于 `D:/anlu/rtl`。官方 MIPI、ISP、DDR2、HDMI、Logo 和 OSD 文件已复制到目标工程。算法路径使用四像素 96 位流，不包含原 `img_accel` 的 CPU AXI 配置、DMA、整帧算法 BRAM 或 CNN 字母识别模块。

主要数据路径：

```text
AWB 96 bit RGB
    -> image_process_stream_96
    -> data_96bit_to_128bit
    -> video_in
    -> DDR2
    -> HDMI mixer
```

## RTL 目录分类

`user_source/hdl_source` 采用与 `la32r_soc/rtl/ip` 一致的功能分层：顶层 wrapper 保留在根目录，其他 HDL 文件按 `ip/camera`、`ip/image`、`ip/video`、`ip/display`、`ip/memory`、`ip/control`、`ip/audio` 和 `ip/platform` 分类。未进入当前 TD 工程的旧版本文件放在对应分类的 `legacy` 子目录中，避免与当前模块重名或误加入编译。

## 说明文件策略

按本次交付要求，已删除工程内全部 `*_spec.md` 文件。迁移范围、接口契约、算法公式、IP来源、验证结果和未运行项目统一写入根目录总说明 PDF：[`PH1P35_image_processing_migration_report.pdf`](../PH1P35_image_processing_migration_report.pdf)。

## IP 来源和边界

- `user_source/ip_source` 不是从 `la32r_soc` 生成的。它是官方 `lab_hd_3_osd` 例程的完整副本，共 53 个文件；目标目录与官方目录逐文件 SHA-256 一致。
- `demosaic_4x_2_0`、`ph1p35_ddr`、`mipi_dphy_rx`、`uics500_cfg` 和 `uiisp_beta` 是官方例程中的安路厂商 RTL/生成文件，迁移时只做了目录归类；五个目录与官方对应目录逐文件一致。
- 当前 TD 工程直接引用的生成 IP 包括官方 PLL、三个 FIFO、AWB 延迟 RAM、divider，以及 DDR2 和 demosaic 的 XML 配置。`MCU` 和 `w40_d512_fifo` 文件随官方 IP 包保留，但当前 `.al` 未直接引用它们的 XML。
- 工程中的 `uial2axis.v` 是官方摄像头视频流接口；这里的 AXI4-Stream 不等同于原 `img_accel` 的 CPU AXI/DMA 控制通路。
- 新增的 `image_process_stream_96.v` 不例化 PLL、FIFO、DDR、MIPI 或其他厂商 IP。它的四组行缓存是普通 Verilog 数组；TD 独立检查已识别出 4 个行缓存 RAM。
- `D:/la32r_soc` 中的 `img_accel.v` 和 `img_accel_calc.v` 只作为灰度、Sobel、腐蚀和膨胀算法参考，没有把其中的 AXI、DMA、CNN 或 Xilinx IP 带入目标工程。

详细文件、哈希和 `.al` 实际引用清单见 [`ip_provenance.md`](ip_provenance.md)。

## 功能 review 结论

- 灰度公式为 `(77 * R + 150 * G + 29 * B) >> 8`，四像素灰度取整数平均。
- Sobel 使用原算法的 `Gx`、`Gy` 和 `abs(Gx) + abs(Gy) > threshold`。阈值默认 24，比较为严格大于。
- 腐蚀和膨胀使用 Sobel 二值结果的因果 3×3 窗口。窗口右下角为当前处理组，`x_group < 2` 或 `y < 2` 输出黑色。
- `image_process_stream_96` 保持四种输出编码：`00` 旁路、`01` 膨胀、`10` 腐蚀、`11` 原图；`isp_top` 在 `00` 模式前置轻量去雾，因而 HDMI 和 CNN 看到去雾后的 RGB/灰度。按键映射已按低有效板载按键要求实现。
- `dehaze_stream_96` 使用四像素组暗通道、两条行缓存、固定大气光和分段透射率增益。它不使用逐像素除法，不改变非 `00` 模式的数据。
- `video_in_dual` 将每个四帧循环槽拆成原图区和处理图区（处理图区偏移 `3_500_000`），两个异步 FIFO 交替写入；`11` 模式读原图区，其余模式读处理图区，因此两份图像可同时保留。
- 算法模块每个有效输入拍产生一个固定延迟4拍的有效输出拍。`tuser`、`tlast`、`tvalid` 和输出数据在流水线中同步传递，不支持暂停式反压。
- AWB 的官方帧开始信号是提前脉冲。`isp_top` 使用 `awb_frame_pending` 将它对齐到 AWB 首个有效 RGB 拍，避免模式和坐标漏锁存。
- 96→128 打包器继续保留官方的提前帧开始通知，因为 `video_in` 用该通知提前复位 DDR FIFO。这个控制信号按官方接口可以独立于 128 位 `valid`，已在根目录总说明 PDF中说明。
- 只使用四组 256 深度的行缓存数组和窗口延迟寄存器，没有新增完整图像缓存。

## 已定位并修复的问题

1. TD 曾报告函数形式参数生成的灰度和 Sobel 网络无驱动。已删除函数式算术，改为显式灰度、符号 Sobel、绝对值和阈值网络；灰度乘法操作数明确扩展为 16 位，避免 Verilog 表达式宽度截断。修复后独立 `check_rtl` 无错误输出。
2. 官方 AWB 帧标记与 AWB 输出有效信号存在延迟差。已在 `isp_top` 增加提前标记缓存和首个有效拍对齐逻辑。
3. 官方工程的 `S_ISP_O_tready` 没有驱动。已在顶层固定为 `1'b1`，保持官方固定速率链路。
4. `image_correction` 实例已命名，固定速率 ready 已连接；同时删除了目标副本中无端口的隐式 `I_raw_tready` 赋值。
5. 96→128 打包器已明确复位、有效间隙和四拍拼接计数行为，保留官方帧开始提前通知契约。
6. 实际 Icarus 仿真发现打包器测试平台的第三拍期望值写错，生产 RTL 拼接结果正确；已修正测试平台并重新运行通过。
7. 原布线关键 Setup 路径把 AWB 输出、灰度乘法、灰度求和、Sobel、绝对值、阈值比较和输出模式选择压在同一拍，导致 `td_phy_retry_pr.timing` 的 Setup WNS 为 `-7.951 ns`。已将图像流改为乘法、灰度、窗口、Sobel/二值和输出选择的多级流水，保留行缓存和标记对齐。重跑综合后 Setup WNS 为 `+0.919 ns`，重跑布局布线后最终 Setup WNS 为 `+0.220 ns`，Setup TNS 为 `0`，失败端点为 `0`。

## 验证结果

| 验证项目 | 结果 | 证据 |
|---|---|---|
| 独立 Python 算法参考模型 | PASS | `sim/run_image_process_reference.py` |
| 去雾定点参考检查 | PASS | `sim/run_dehaze_reference.py` |
| TD 6.2 工程源分析/展开 | PASS（源分析与 `video_in_dual` 展开） | `PRJ-1401`，97 个源文件；工具在既有加密宏库阶段触发 `macrolib.cpp` 断言 |
| 原图、Sobel、腐蚀、膨胀 | PASS | 参考模型覆盖四种模式 |
| 恒定图、水平边缘、垂直边缘、渐变、单点 | PASS | 参考模型测试矩阵 |
| 阈值 1019、1020、1021 边界 | PASS | 覆盖等于、低于和高于梯度的比较行为 |
| 帧内改变模式和阈值 | PASS | 首拍锁存测试 |
| 两帧 1024×600 组计数 | PASS | 每帧 `153600` 个有效组、`600` 个行结束、每帧 `1` 个帧开始 |
| AWB 提前帧标记对齐 | PASS | 参考模型桥接检查 |
| 96→128 拼接顺序参考检查 | PASS | 参考模型拼接检查 |
| 96→128 输出标记对齐 | PASS | 参考模型确认每帧 115200 个 128 位输出拍、每行一个 `tlast` |
| TD 独立图像流、模式选择器和 96→128 打包器 `check_rtl` | PASS | [`td_reorg_core_check.log`](td_reorg_core_check.log)；图像流识别 4 个行缓存 RAM；三模块均完成分析 |
| 完整工程源文件分析 | PASS | [`td_reorg_source_check.log`](../td_project/td_reorg_source_check.log)；`PRJ-1401 : Successfully analyzed 88 source files.` |
| 完整工程顶层层次展开 | 历史 PASS；本次双路缓存增量分析展开到 `video_in_dual` 后触发既有加密宏库断言 | 官方历史日志见 [`td_syn_retry_final.log`](td_syn_retry_final.log)；本次使用 `E:\Software\TD5.6.2\bin\td_commands_prompt.exe` |
| TD 综合 | PASS | 采用流水线修改后的 RTL 重跑 `optimize_rtl`、`optimize_gate`，并导出 `camera_to_dsi_display_gate.db`；Setup WNS `+0.919 ns`、TNS `0`、失败端点 `0`；日志见 [`td_syn_timing_pipeline_20260902.log`](td_syn_timing_pipeline_20260902.log) |
| TD 布局布线 | PASS | 从新 gate 数据库导入后，`place`、`route` 和 `fix_hold` 完成，并导出新的 PR 数据库；最终 Setup WNS `+0.220 ns`、TNS `0`、失败端点 `0`；日志见 [`td_phy_timing_pipeline_20260902.log`](td_phy_timing_pipeline_20260902.log) |
| TD 资源报告 | PASS（已生成） | 新布局后资源报告见 [`td_phy_timing_pipeline_phy.area`](td_phy_timing_pipeline_phy.area)：15327/21216 slice、30/108 eRAM、21/40 DSP、6/12 DDR byte、1/2 MIPI RX、3/6 PLL |
| TD 时序 | PASS | 最终布线时序见 [`td_phy_timing_pipeline_pr.timing`](td_phy_timing_pipeline_pr.timing)：Setup WNS `+0.220 ns`、TNS `0`、失败端点 `0`；Hold WNS `+0.020 ns`、TNS `0` |
| 事件驱动 RTL 仿真 | PASS | 本机 Icarus 对图像流、96→128打包器、模式选择器和图像流到打包器集成边界分别编译并运行通过；日志见 [`rtl_simulation_timing_pipeline_20260902.log`](rtl_simulation_timing_pipeline_20260902.log) |
| 开发板、SC500CS 摄像头、HDMI | NOT RUN | 当前会话没有硬件验证条件 |

## 严格代码门禁

历史严格门禁结果如下；本次不把它们作为综合或时序通过证据：

- `image_process_gate.json/.md`：493 个错误、4 个严格警告。
- `mode_selector_gate.json/.md`：69 个错误、1 个严格警告。
- `data96_128_gate.json/.md`：105 个错误、3 个严格警告。

这些结果表示严格门禁未达到 delivery-ready。主要问题是门禁的命名、注释覆盖、ANSI 端口风格、组合逻辑预算和未复位行缓存的规则。行缓存未清零是为了保持 RAM 推断，并且前两行/前两列输出在算法逻辑中被强制屏蔽；组合逻辑路径仍必须在可用 TD 版本中完成时序分析，不能用本报告替代时序结论。

## 主要文件

- [TD 工程](../td_project/camera_to_dsi_display.al)
- [顶层 wrapper](../user_source/hdl_source/design_top_wrapper.v)
- [模式选择器](../user_source/hdl_source/ip/control/mode_selector.v)
- [96 位图像处理流](../user_source/hdl_source/ip/image/image_process_stream_96.v)
- [轻量去雾流](../user_source/hdl_source/ip/image/dehaze_stream_96.v)
- [双图像 DDR 写入器](../user_source/hdl_source/ip/video/video_in_dual.v)
- [ISP 顶层](../user_source/hdl_source/ip/image/isp_top.v)
- [96→128 打包器](../user_source/hdl_source/ip/image/data96_128/data96_128.v)
- [图像处理测试平台](../sim/tb_image_process_stream_96.sv)
- [模式选择测试平台](../sim/tb_mode_selector.sv)
- [打包器测试平台](../sim/tb_data96_128.sv)
- [图像流到打包器集成测试平台](../sim/tb_stream_pack_integration.sv)
- [独立参考模型](../sim/run_image_process_reference.py)
- [迁移总说明 PDF](../PH1P35_image_processing_migration_report.pdf)
- [验证汇总](verification_summary.md)
