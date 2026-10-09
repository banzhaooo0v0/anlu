# C50C 与 FPGA 的串口对接固件

> 来源说明（2026-10-09）：下文为队友随包交付的说明，其中“本次编译/本机”指上游环境。当前项目只导入源码和预编译产物，尚未在本机重编译或烧写。当前可运行的完整性校验是仓库根目录的 `python scripts/verify_stm32_delivery.py`；下文 `verify_package.py` 依赖队友原始厂商目录，不能直接用于本机。当前 FPGA 的接线、720p 模式与验证状态以根目录 README 为准。

本目录是厂家 `WHEELTEC_C50X_2025.12.26` 源码的独立副本。保留 STM32 电机 PI、编码器、运动学、车型电位器、急停和失能逻辑；FPGA 通过 USART3 发送速度并接收状态。本次没有向小车下载程序。

## 交付文件

- `WHEELTEC_C50X_FPGA_PD89/USER/WHEELTEC.uvprojx`：完整 Keil 工程，包含厂家五个车型目标。用户照片是普通轮四驱，编译时明确选择 **4WD_Car**，不要使用工程列表首项 Akm_Car。
- `WHEELTEC_C50X_FPGA_PD89/OBJ/cli_4WD/4WD_Car_FPGA_PD89.hex`：本次 ARMCC CLI 生成的四驱 HEX；同目录包含 BIN、AXF、MAP。起始地址 `0x08000000`，不是偏移到 `0x08010000` 的无线 bootloader 固件。
- `uart_pd89_watchdog.patch` 与 `patch_manifest.json`：精确修改和修改前后 SHA-256；patch 用 UTF-8 展示，实际厂家 C/H 文件保留原 GBK 字节。不要把 UTF-8 patch 不经编码处理应用到 GBK 原文件，直接使用已修改的副本即可。
- `build_armcc.py`、`build_armcc.log`、`build_commands.json`：本地 ARMCC 5 编译脚本、编译结果、完整命令清单。
- `verify_package.py` 与 `verification.json`：复制范围、输入完整性、HEX 校验、向量表和产物摘要验证。
- `verify_compiler_contract.py` 与 `compiler_contract.json`：用 ARMCC 实际预处理检查默认启动代码没有主动前进、显式开启诊断可恢复原逻辑，并编译检查 PD8/PD9 引脚宏。

## 精确改动

1. `HARDWARE/Inc/uartx.h`：USART3 从厂家默认 PB10/PB11 切到预留分支 PD8/PD9；修正该分支的 `UART3_PIN_TX/RX` 为初始化函数实际引用的 `UART3_TX_PIN/RX`。PD8 是 TX，PD9 是 RX，AF7。
2. `SYSTEM/sys/sys.c`：`SecurityLevel=0`，启用厂家控制命令超时保护。
3. `BALANCE/balance_task.c`：命令丢失计数饱和到 101，避免 u8 回绕；100 Hz 任务中超过 100 次未刷新后将 Vx/Vy/Vz 目标清零，约 1.01 秒。真实停车还受原厂速度平滑、PI 和机械惯性影响。
4. `BALANCE/Inc/balance_task.h` 及 `BALANCE/balance_task.c`：新增 `FPGA_ENABLE_STARTUP_MOTION_CHECK`，默认 0。关闭厂家上电约 10–12 秒的 `Drive_Motor(0.2f,0,0)` 主动运动诊断，期间保持目标零并完成 `check_end` 标志；原诊断代码保留，只有明确设成 1 才开启。

开机运动诊断检查编码器接错、未连接和过载，不进行方向自动校准。默认关闭后，这段主动诊断的报错功能也被关闭；原急停、低压保护和其他电机控制逻辑保持。原串口前 10 秒丢弃命令，约 12.3 秒后进入正常运动控制，这两个等待条件未改。第一次联调等待约 15 秒，并从零速度开始。

## C50C V2.0 接线

依据本地厂家 `C50C-V2.0原理图.pdf` 的 HDR2 GPIO 排针，以及代码的 USART3 AF7 分配：

| FPGA 信号 | C50C V2.0 信号 | HDR2 针号 |
|---|---|---:|
| FPGA UART TX | PD9 / USART3 RX | 15 |
| FPGA UART RX | PD8 / USART3 TX | 16 |
| GND | GND | 4、19、20 任一个 |

两块板连接 TX、RX、GND，逻辑电平 3.3V；各自按手册供电，不把小车 24V 电池或两个板子的电源输出接到串口。根据连接器 1 脚标记数针，不按照片左右猜测。这张引脚表只适用于原理图所对应的 **C50C V2.0**；其他修订需核对。

原理图路径：`D:/qrsfpga/car/2.WHEELTEC R550 PLUS ROS大型科研机器人系列资料/4.芯片数据手册与原理图/主控制器_C50C版/原理图与资源分配图/V2.0版/C50C-V2.0原理图.pdf`。

改脚后，板载 USART3 的 USB 转串口通信路径 PB10/PB11 不再用于这条链路。USART1、蓝牙 USART4 没有改脚。STM32 烧录与 FPGA 下载仍分别使用各自工具；这份 HEX 应在核对主控版本、编码器和车型目标后使用。

## 实际协议

UART 为 **115200 bit/s、8 数据位、无校验、1 停止位、无流控**，发送二进制字节，不能发送十六进制的 ASCII 字符串。UART 字节内部低位先发；16 位字段在帧中高字节在前。

控制帧共 11 字节：

| 下标 | 内容 |
|---|---|
| 0 | 0x7B |
| 1 | 模式 0：普通速度控制 |
| 2 | 保留，本接口固定 0 |
| 3、4 | Vx，int16 大端，单位 mm/s |
| 5、6 | Vy，int16 大端，单位 mm/s；普通轮四驱固定 0 |
| 7、8 | Wz，int16 大端，单位 mrad/s；源码称 Vz |
| 9 | 下标 0–8 所有字节异或 XOR/BCC |
| 10 | 0x7D |

前进 0.10m/s：`7B 00 00 00 64 00 00 00 00 1F 7D`。
停车：`7B 00 00 00 00 00 00 00 00 7B 7D`。
后退 0.10m/s：`7B 00 00 FF 9C 00 00 00 00 18 7D`。
建议 FPGA 每 20ms 发一帧，停止时继续发零速度。FPGA 上层命令超时后必须清零，不能周期重发过期非零速度，否则 STM32 的链路超时保护不会触发。

模式 0 从 USART3 收到后选择 `_ROS_Control`；这只是源码的控制模式名称，不要求 FPGA 运行 ROS。

反馈共 24 字节，`BALANCE/data_task.c` 每 50ms 左右发送：

| 下标 | 内容 |
|---|---|
| 0 | 0x7B |
| 1 | FlagStop，1 为失能/禁止电机，0 为允许；不是命令超时原因码 |
| 2–7 | 三组 int16 大端速度，Vx/Vy 除 1000 为 m/s，Wz 除 1000 为 rad/s |
| 8–13 | 三组 int16 大端加速度原始值 |
| 14–19 | 三组 int16 大端陀螺仪原始值 |
| 20、21 | 电压 mV，高字节在前；正常电池电压为正值 |
| 22 | 下标 0–21 字节异或 XOR/BCC |
| 23 | 0x7D |

IMU 已按原代码变换坐标：X=原 Y，Y=-原 X。Z 陀螺仪低于原阈值会被置零。量程与物理单位必须结合实际 IMU 初始化核对；此协议没有直接输出二维位置。自动回充硬件启用时会追加 `0x7C ... 0x7F` 的 8 字节回充帧，接收器应检查 24 字节候选帧长度、尾、XOR 后才发布状态。

## 型号与解析边界

`TYPE:3` 只有结合编译目标才有含义：在 **4WD_Car / _4WD_CAR** 目标中，`CarType/4wd_robot_init.c` 的 case 3 选择 `SENIOR_4WD_DL`、MD36N_51、GMR_500 和 152mm 轮径。没有把 TYPE 写死为 3，厂家电位器选择逻辑和轮距/轴距/PI 参数保持原样。本次不能仅凭 OLED 的数字证明车里当前固件一定是这个目标。

厂家接收器找 0x7B 后固定收满 11 字节再检查，不在帧中遇到 0x7B 就重新开始，也没有逐字节超时；一个丢字节/噪声可能导致本帧失效，之后重新找帧头。有效控制数据自身也可能包含 0x7B/0x7D，所以不能用分隔符字符串方式处理。不同串口共享接收计数，交错控制会互相打断；联调时只使用一个控制来源。

原保护逻辑会被任意帧尾和 XOR 合格的串口控制帧、CAN 控制刷新，不局限于本接口模式 0。如果其他控制器同时不断发送合法帧，不能假定 FPGA 断线必然触发保护。此包使用模式 0 连续帧，未扩展厂家帧格式或更改接收解析器。

## 构建与验证

在安装 ARMCC 5 的环境运行：

```powershell
python .\build_armcc.py --toolchain D:\keil5\ARM\ARMCC\bin
python .\verify_package.py
python .\verify_compiler_contract.py
```

脚本从 uVision XML 获取四驱目标的源文件、IncludePath、Define 和排除文件；使用 Cortex-M4 单精度 FPU、C99、O3、MicroLIB、逐函数 section；链接到 0x08000000、512KB Flash、128KB SRAM。它不执行厂家递归删除 HEX 的前置批处理，也不下载到设备。Keil 工程原声明 ARMCC 5.06 update 7；本机可用 5.06 update 5，已成功编译四驱目标，0 错误，1 个默认关闭诊断造成的 unused-function 警告。未对另外四个目标逐一编译。

已完成编译、HEX 校验和向量/内存范围检查；没有实物串口、电机、编码器或断线停车测试。首次硬件验证架空车轮，保证使能/急停可操作，依次验证零速度、低速前进/后退、停发超过 1 秒、恢复零帧，最后再落地。
