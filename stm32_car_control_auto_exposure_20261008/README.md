# FPGA 与 STM32 小车控制对接（1280×720，自动曝光与帧同步修复版）

本目录是独立交付版本。唯一随本目录上传的 FPGA bit 是
`fpga/traffic_sign_td/td_project/bitstream/traffic_sign_td_frame_sync_fix.bit`
（SHA-256：`EF97A5D1A038C0BAB7C2DEF67A1533A9BEB3C0E1D602172E82BC9BD60D4EBAB2`）。
它由 2026-10-08 21:14 的 TD 构建生成，包含 SC500CS 自动曝光和帧开始提前通知修复；旧 bit 与 TD 临时构建目录没有上传。

基于队友仓库 [hfuxb/anlu 的 main](https://github.com/hfuxb/anlu/tree/main)，本次基线为 `c37b61cc31d9dc6ba8713a95a0caffe067c5c77d`。本包实现你负责的小车控制接口：识别结果跨时钟传递、控制状态机、UART 速度指令、状态反馈，以及 C50C 的配套串口改脚和断联停车。STM32 继续执行四个电机的编码器与 PI 闭环。

本版将摄像头采集、ISP 和 HDMI 统一为 **1280×720**，采用 SC500 720P 例程的寄存器配置和 PLL。小车 RTL 和 STM32 固件保持不变。HDMI 像素时钟为例程实际的 75MHz，1650×750 总时序对应约 60.61Hz。

2026-10-08 修复：`hdmi_tx.v` 内部参数同步为 1280×720、总时序 1650×750、VIC=4；新增 SC500CS 自动曝光。帧开始信号恢复为官方例程的提前通知，使 `video_in` 的 FIFO 复位在首批有效像素进入前完成。

任务二按键版在此基础上加入板载 **KEY4 短按循环切换画面**，屏幕显示 `MODE:RAW/ERO/DIL/SIG`。KEY4 长按仍是小车限速；KEY1–KEY3 小车控制不变。识别结果文字为 `DIR:L/R/?`，OSD 字库包含 `?` 字形。

## 打开哪个文件

| 文件/目录 | 用途 |
|---|---|
| `rtl/` | 你负责的 8 个 Verilog 模块，统一入口 `car_control.v` |
| `fpga/traffic_sign_td/td_project/traffic_sign_td.al` | 已接入队友 main 的完整 TD 工程，顶层仍是 `design_top_wrapper` |
| `integration/build_bit.tcl` | TD 完整构建脚本 |
| `stm32/WHEELTEC_C50X_FPGA_PD89/USER/WHEELTEC.uvprojx` | 已修改的完整 Keil 工程，选择 `4WD_Car` |
| `stm32/WHEELTEC_C50X_FPGA_PD89/OBJ/cli_4WD/4WD_Car_FPGA_PD89.hex` | 本次编译成功的 STM32 四驱固件 |
| `fpga/traffic_sign_td/td_project/bitstream/traffic_sign_td_frame_sync_fix.bit` | 新编译的自动曝光、帧同步修复 FPGA bit |
| `sim/` | 可重跑的自检仿真 |
| `tools/car_packet.py` | 二进制协议编码、反馈解码，运行时不打开串口 |

## FPGA 的运行行为

1. 上电只发零速度，每 20ms 发一帧。没有新的识别结果、没有正确反馈或 STM32 失能时，不能启动。
2. 摄像头识别正在更新、STM32 反馈 `FlagStop=0` 时，按 **KEY1** 启动，以 **0.10m/s** 前进。
3. 连续 **3 个新结果**都为 `L` 或 `R` 时，以 0.05m/s、角速度 ±0.25rad/s 转动 **800ms**，然后前进。同一个持续出现的标志只触发一次；转动结束后连续 3 个 `?` 才允许再次触发。
4. **KEY2** 停车，**KEY3** 模拟外部障碍停车，按住 **KEY4** 限速到 0.05m/s。KEY4 短按释放时还会切换视频模式；按下期间限速会短暂生效。KEY2/KEY3 停车后须重新按 KEY1；释放停车按键不会自动恢复。
5. 超过 **500ms** 未收到新的识别结果或合法 STM32 反馈、或反馈表示失能，立即将目标速度置零并锁住启动状态。停止时保持零速心跳；停止发生在已发送的整帧中途时，完整发完当前帧后立即补发零帧，115200 下整帧约 0.96ms。
6. STM32 另有约 **1.01s** 无有效控制帧的保护。目标清零不等于机械瞬间静止，仍受到电机 PI、速度平滑与惯性影响。

这是低速联调策略。队友当前检测器只输出 `L/R/?`，其中 `?` 同时包括未知和无目标；它没有输出障碍识别或置信度。KEY3 是外部停车输入的演示，不是已经实现视觉避障。800ms 转弯是时间控制，不保证固定转角，也没有在 FPGA 中实现角度/路径闭环。相关速度、确认帧数和计时参数在 `car_decision.v`、`car_control.v` 中。

## 图像模式切换

在板载 KEY4 上短按并松开（少于约 0.5 秒），依次切换 `MODE:RAW` 原图 → `MODE:ERO` Sobel 二值结果腐蚀 → `MODE:DIL` Sobel 二值结果膨胀 → `MODE:SIG` 原图及方向识别文字 → 原图。切换在松开时生效，屏幕左上区域的 `MODE:` 在下一帧更新。`SIG` 模式下出现 `DIR:WAIT` 或 `DIR:L/R/?`。长按 KEY4 超过约 0.5 秒不会切换，仍执行小车限速。原有扩展口两路模式输入保留：其值不是 `11` 时优先于 KEY4 选择。

图像模式仅改变显示内容；路牌检测器仍持续运行，小车控制不会因为切换到 RAW/ERO/DIL 而停用识别。测试时可先让车轮离地，或不接小车，只观察 HDMI。KEY4 是复用按键，按下期间车速限值会短暂降低。

## 实物接线

**适用条件：HX1P35A 与 C50C V2.0，STM32 使用本包的 PD8/PD9 固件。先分别断电再接线，逻辑电平 3.3V TTL。**

| HX1P35A | 方向 | C50C V2.0 |
|---|---|---|
| J1 扩展口第 **1** 脚，GPIOA_0，FPGA **C18 / TX** | → | HDR2 第 **15** 脚，**PD9 / USART3 RX** |
| J1 扩展口第 **2** 脚，GPIOA_1，FPGA **D15 / RX** | ← | HDR2 第 **16** 脚，**PD8 / USART3 TX** |
| J1 第 **12 或 30** 脚 GND | — | HDR2 第 **4、19 或 20** 脚 GND，任选一个 |

只跨接 TX、RX、GND。两板各自供电，不跨接 5V/3.3V 输出，也不接小车 24V 到 FPGA；这里的串口不是 Type-C 的 D+/D−。依据排针 1 脚标记和缺口确认针号，不根据照片左右推断。FPGA 板载 USB-UART 没有接到 C18/D15，不能指望插 USB 就直接观测这条外部链路。

引脚依据：本地 `新HX1P35A开发板手册-HDL版2604.pdf` **第7页** J1 表、第22–23页 KEY1–4 表；`C50C-V2.0原理图.pdf` 的 HDR2。完整原始路径见 `docs/pin_evidence.md`。KEY1=D5、KEY2=A9、KEY3=B9、KEY4=C7，均为按下低电平。

## 首次使用顺序

1. 核对小车实际主控版本、四驱普通轮和车型参数。本包使用厂家 `4WD_Car` 目标；OLED 的 `TYPE:3` 本身不能证明当前固件目标。原有车型电位器、轮距/轮径和 PI 参数保留。
2. 将本包 STM32 工程编译/下载到 C50C，或使用已经生成的 HEX。此固件在 `0x08000000` 起始，不适用于要求 `0x08010000` 偏移的无线 bootloader 下载。USART3 改脚后，原 PB10/PB11 的 USB 转串口不再用于这条控制链路。
3. TD 打开上述 `.al`，使用 `bitstream/traffic_sign_td_frame_sync_fix.bit` 下载 FPGA。此 bit 含摄像头、自动曝光、ISP、路牌识别、DDR、HDMI、板载 KEY4 模式切换、问号字形和小车串口接口，配合第 2 步的 STM32 固件使用。修改源码或约束后，需要重新完成综合、布局布线和 bitgen。
4. 断电接好上述三根线；摄像头按前面核对过的官方**同向排线**要求连接，不能使用厂赠异向线尝试上电。
5. 首次架空车轮，保留可操作的原车使能/急停。分别供电，等 **15 秒**左右（厂家启动等待仍保留），确认摄像头结果持续更新、串口反馈有效、原车允许电机，再按 KEY1。
6. 先检查零速、低速前进与左右方向，按 KEY2/KEY3 验证停车，再分别停掉识别更新和断开串口验证超时；最后才落地。恢复通信不应自动起步，需再次按 KEY1。

本次交付的是代码和编译/仿真证据，没有替你下载本包 FPGA 或 STM32 程序，也没有进行实车运动验证。

这个新 bit 已通过 TD 综合、布局布线和 bitgen；帧同步修复仍需在实际屏幕上确认右侧画面错位是否消失。

## 复现检查

安装 Vivado 2019.2 的机器可运行 `sim/run_sim.ps1`（小车接口）及 `sim/video720/run_video_sim.ps1`（720P 视频）。STM32 构建和验证命令见 `stm32/README.md`。协议工具仅依赖 Python 标准库：

```powershell
python .\tools\car_packet.py selftest
python .\tools\car_packet.py encode --vx 100 --wz 0
python .\tools\car_packet.py encode
```

生成的是要勾选“十六进制发送”的字节列表，不是发送 ASCII 字符串 `7B ...`。停车包为 `7B 00 00 00 00 00 00 00 00 7B 7D`。反馈是 24 字节二进制，文本模式显示乱码是正常现象。
