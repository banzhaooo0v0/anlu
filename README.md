# 安路 PH1P35：720p 图像处理与视觉小车

本工程在原有去雾、原图/处理图双缓存和 CNN 基础上，整合队友的蓝底白箭头识别、STM32 小车控制、逐像素腐蚀/膨胀，并统一为 **1280×720**。

当前工程入口：`td_project/camera_to_dsi_display.al`；顶层：`design_top_wrapper`；器件：`PH1P35MDG324`，speed 3。

**当前 720p 版本：15 项功能仿真及去雾/双图 DDR 回归通过，TD 综合、布局布线、最终约束时序和 bitstream 生成通过。** 最终 Setup WNS +0.115 ns、Hold WNS +0.020 ns，TNS 均为 0。[本次整合报告](reports/integration_20261009.md) 记录了工具崩溃及恢复过程；[720p bitstream](release/720p_20261009/camera_to_dsi_display_720p.bit) 与 [校验清单](release/720p_20261009/manifest.json) 单独保存，不受重置 TD 运行目录影响。当前未连接开发板，未执行烧写、摄像头实拍或电机运动测试。

最终 slice 占用 95.32%、eRAM 占用 97.22%，且 hold 裕量仅 0.020 ns；后续改源码、IP 或约束必须重新验证。10 月 8 日的 1024×600 实现报告和 bitstream 不代表本次 720p 版本。

## 已实现功能

| 功能 | 当前行为 |
|---|---|
| 720p 摄像头输入和显示 | SC500CS 原生 1280×720 RAW10，2-lane MIPI；ISP、行缓存、DDR、HDMI 使用同一画幅，取消原 1024×600 裁剪模块 |
| 自动曝光 | 使用队友 RAW 绿色分量测光逻辑，暗场提高曝光/增益，亮场降低；曝光范围 6–1990，适配 720p VTS=1000 的配置 |
| 原图与处理图 | 同一帧分别写入 DDR 原图区和处理图区；可切换显示，两路一直保留 |
| 轻量去雾 | 流式暗通道近似、透射率下限、定点增益和饱和，四像素/拍；不需要整帧算法缓存 |
| 腐蚀/膨胀 | 每个 RGB 像素分别转灰度、Sobel 二值化，再做因果 3×3 腐蚀或膨胀；正确处理四像素组之间的邻接关系 |
| 方向识别 | AWB 彩色图 → 蓝色分割 → 单候选框 → 下一帧框内白色像素左右投票，输出 `L`、`R`、`?` |
| 小车控制 | 识别结果跨时钟域传给控制器；UART 周期发送速度，检查 STM32 反馈、视觉超时、按键停车/障碍输入 |
| 屏幕文字 | `MODE:RAW/ERO/DIL/HAZ`、`DIR:WAIT/L/R/?`；HAZ 模式保留原 `CNN:` 字母识别显示 |
| 原 CNN | 保留原网络和权重；采样器适配 1280×720 → 64×64，每单元平均 20×11 或 20×12 个像素 |

方向识别始终使用 **AWB 后、去雾前的 RGB**，不受显示模式影响。它与原 CNN 是两条独立路径，小车使用 `DIR` 结果。方向检测采用单外接框，不是通用目标检测或连通域分割；多个蓝色区域可能合并，`?` 同时表示无目标或无法判定。其准确率仍需用实际赛道画面测量。

“原图”指 AWB 后的 RGB，不是传感器 Bayer RAW。两份图存于循环 DDR 帧缓存；没有新增 SD 卡保存或 USB 导出功能。每帧每路为 2,764,800 字节，即 172,800 个 128 位数据字。四个帧槽基址为 0、7,000,000、14,000,000、21,000,000；处理图偏移 3,500,000，沿用 DDR 接口地址单位，每个 128 位字地址递增 8。

## 使用画面模式

外部 `I_button[1:0]` 保持 `11` 时，板载 **KEY4 短按后松开**循环切换：

| 模式位 | 屏幕文字 | 输出画面 |
|---|---|---|
| `11` | RAW | AWB 原图 |
| `10` | ERO | Sobel 二值边缘的 3×3 腐蚀 |
| `01` | DIL | Sobel 二值边缘的 3×3 膨胀 |
| `00` | HAZ | 去雾彩色图，并运行原 CNN |

KEY4 长按约 0.5 秒以上，松开时不切模式；按住期间同时给小车降速输入。外部模式位不为 `11` 时优先使用外部选择。模式和阈值在算法帧首锁存，DDR 缓存使可见画面切换存在帧延迟。形态学使用上方/左侧窗口，输出不是中心对齐的离线图像滤镜；顶端前两行输出黑边，左侧缺失邻居补零。

HDMI 为 1280×720 有效区，行总长 1650，帧总高 750，水平前肩/同步/后肩 110/40/220，垂直为 5/5/20。采用队友 PLL：HDMI 像素约 75 MHz、串行约 375 MHz，计算显示刷新约 **60.61 Hz**，不是精确 74.25 MHz 的标准 60 Hz。摄像头 MCLK 约 23.81 MHz。接收端兼容性仍需实机确认；时序约束按 720p 传感器配置中的 480 Mb/s/lane 设置 MIPI 时钟上限关系。

## 小车接线与操作

适用接线依据为队友提供的 HX1P35A / C50C V2.0 资料，见 [引脚依据](docs/teammate_pin_evidence.md)。FPGA 封装引脚已加入 `user_source/constraints_source/pin.adc`。

| FPGA 信号/操作 | FPGA 封装脚 | 对端或作用 |
|---|---|---|
| `O_car_tx` | C18 | → STM32 PD9 / USART3 RX，HDR2 第 15 脚 |
| `I_car_rx` | D15 | ← STM32 PD8 / USART3 TX，HDR2 第 16 脚 |
| GND | 板上 GND | 与 STM32 共地，HDR2 第 4/19/20 脚之一 |
| KEY1 `I_car_arm_n` | D5 | 通信和视觉正常时按下，允许运行 |
| KEY2 `I_car_stop_n` | A9 | 停车并解除运行许可，恢复需重新按 KEY1 |
| KEY3 `I_car_obstacle_n` | B9 | 外部障碍/演示停车输入，不是摄像头障碍识别 |
| KEY4 `I_car_slow_n` | C7 | 按住降速，短按释放切换显示模式 |

串口是 **3.3V TTL、115200、8N1**，连接 TX/RX/GND，双方各自供电。按键低有效。不要把 RS232 电平或小车电池电压接到 FPGA IO。

使用步骤：

1. STM32 打开 `stm32/WHEELTEC_C50X_FPGA_PD89/USER/WHEELTEC.uvprojx`，选择 **4WD_Car**。随包 HEX 是队友生成的产物，本机未重编译；烧写基址 `0x08000000`，不适用于 `0x08010000` bootloader 偏移方案。详情见 [STM32 说明](stm32/README.md)。
2. 在完整 FPGA 实现通过、核对实际板卡后，分别使用各自工具下载；本次操作没有下载硬件。
3. 首次联调架空车轮，上电约等 15 秒。FPGA 默认持续发送零速度，收到有效反馈且 `FlagStop=0`、视觉结果保持更新后，KEY1 才能启动。
4. 默认前进 100 mm/s；KEY4 按住为 50 mm/s。连续 3 个相同的 `L/R` 结果，执行 800 ms 转向：前进 50 mm/s，角速度 ±250 mrad/s。这是定时转向，不是角度闭环。
5. 同一路牌不会连续反复触发转弯；需连续 3 个 `?` 清除转向锁后再次识别。无新结果或无有效反馈超过 500 ms、`FlagStop!=0`、KEY2/KEY3 有效时发送零速度并解除许可；条件恢复后重新按 KEY1。

新鲜的 `?` 属于有效视觉心跳，并不会自动停车；启动后仍可直行。真正的视觉超时指没有新识别结果。停止时仍每 20 ms 发送零速度心跳。STM32 另有约 1.01 秒的命令丢失保护；实际减速受原厂 PI、速度平滑和机械惯性影响。

## 串口协议和工具

控制帧共 11 字节：`7B 00 00 Vx_hi Vx_lo Vy_hi Vy_lo Wz_hi Wz_lo BCC 7D`。速度字段是有符号 int16、大端；Vx/Vy 单位 mm/s，Wz 单位 mrad/s；普通四驱 Vy 为 0，BCC 是前 9 字节异或。反馈为 24 字节，包含 FlagStop、速度、IMU 原始量和电压，尾部同样检查 BCC。发送的是二进制字节，不能发送十六进制文本。

```powershell
cd E:\FPGA\workspace\anlu
python tools/car_packet.py encode --vx 100
python tools/car_packet.py encode --vx 0 --wz 0
python tools/car_packet.py selftest
```

这些命令只生成/验证协议数据，不打开串口、不控制实际车辆。

## 构建和离线验证

```powershell
cd E:\FPGA\workspace\anlu
# 功能测试：720p HDMI、CNN 采样、曝光、形态学、识别、小车和串口。
./sim/run_teammate_features.ps1
# 只运行一个测试，例如方向识别。
./sim/run_teammate_features.ps1 -Test tb_traffic_sign_detector_96
# 原图/去雾图 → 两路打包/FIFO → DDR 写入，720p 两帧。
./sim/run_member2_integration.ps1
# 去雾逐拍参考比对、AWB RAM 容量/地址等价性（含 1280 宽）。
./sim/run_member2_rtl.ps1
# STM32 交付哈希、Keil 源文件、HEX 校验和 BIN/向量表检查。
python scripts/verify_stm32_delivery.py
# TD 完整综合；加 -Physical 继续布局布线和 bitgen。
./scripts/run_td_verify.ps1 -Physical
```

仿真使用本机 **Vivado XSim 2019.2**，可通过 `-VivadoBin` 修改安装路径。TD 用于安路综合/实现，不能把 XSim 通过写成“TD 全系统仿真通过”。CNN 测试使用 `CNN_SIM` 行为 RAM，AWB 等价测试使用显式行为 RAM；未验证厂商加密原语。集成图像测试从 AWB RGB 后开始，不模拟真实传感器、DDR PHY、电机和整条物理链路。

两个 `run_member2_*` 脚本共用 `sim/build_dual`，请依次运行。TD 脚本会重置现有运行产物；综合失败后立即停止，不继续用旧网表布局布线；日志存入 `reports`。当前 TD 版本的自动多线程详细布线及压缩 bitgen 均发生过内部崩溃，工程物理实现策略及脚本默认改用**单线程、关闭 bitstream 压缩**；`-Threads auto` 可恢复工具自动选择，但本机不推荐。未压缩 `.bit` 保持同一设计功能，文件更大。最终可烧写版本必须以本次完整实现及最终布线时序为准。

如仅详细布线发生崩溃，且 `phy_1/camera_to_dsi_display_place.db` 确实来自当前源码已完成的布局，可用下面的恢复入口；源码、IP 或约束改动后必须重新完整构建，不能复用旧布局：

```powershell
cd E:\FPGA\workspace\anlu\td_project\camera_to_dsi_display_Runs\phy_1
& E:\Software\TD5.6.2\bin\td_commands_prompt.exe ../../../scripts/resume_td_route.tcl
```

恢复入口固定为单线程且关闭压缩，生成最终 `.timing` 与 `.bit`。如布线已通过，仅 bitgen 失败，在同一目录执行 `td_commands_prompt.exe ../../../scripts/resume_td_bitgen.tcl`，可从当前 `camera_to_dsi_display_pr.db` 独立生成未压缩 `.bit`。完成后仍需核对 setup/hold WNS 非负、TNS 为 0；仅出现 bit 文件不代表时序通过。

## 目录导航

- `user_source/hdl_source/ip/image/traffic_sign/`：方向识别及 HDMI 结果跨域。
- `user_source/hdl_source/ip/car/`：按键、视觉跨域、决策、UART 命令发送与反馈解析。
- `user_source/hdl_source/ip/image/`：去雾、逐像素形态学、AWB、CNN、ISP 集成。
- `user_source/hdl_source/ip/camera/config/`：720p SC500CS 配置、自动曝光。
- `stm32/`：队友 STM32 工程、预编译固件及上游验证资料。
- `sim/teammate_features/`：本次功能测试；`reports/`：本地验证证据。
- [COMMIT.md](COMMIT.md)：面向团队的提交说明、使用方式及验证边界。
