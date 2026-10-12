# 去雾、整合 720p 路牌识别、小车控制与逐像素形态学处理

## 功能说明

本工程面向 PH1P35 开发板和 1280×720 摄像头视频流，提供以下功能：

- 摄像头采集、自动曝光、AWB、DDR 帧缓存和 HDMI 显示保持 1280×720 同一画幅。
- RAW 模式显示 AWB 后的原图，HAZ 模式显示彩色去雾图；原图和处理图同时写入独立 DDR 区域，便于实时对照。
- 去雾采用流式暗通道近似、因果 3×3 局部最小值、透射率下限和逐像素 RGB 恢复。算法每拍处理四个 RGB888 像素，不使用整帧算法缓存，适合实时视频。
- 方向识别从 AWB RGB 中提取蓝底白箭头路牌，输出 `L`、`R` 或 `?`，与显示模式独立运行。
- 保留原 CNN 字母识别路径，输入采样适配 1280×720 摄像头画面。
- 对 Sobel 二值图执行逐像素 3×3 腐蚀和膨胀，支持四像素并行处理和跨组邻接。
- 通过 115200、8N1 串口向 STM32 发送速度命令，接收反馈并执行启动、停车、降速、定时转弯和通信超时保护。

## 显示和小车操作

外部模式位保持 `11` 时，KEY4 短按后松开循环选择显示内容：

| 模式 | 屏幕内容 | 作用 |
|---|---|---|
| RAW | AWB 原图 | 观察摄像头原始彩色画面 |
| ERO | 腐蚀结果 | 减少 Sobel 二值图中的孤立亮点 |
| DIL | 膨胀结果 | 连接相邻边缘区域 |
| HAZ | 去雾彩色图 | 提升雾天场景的局部层次，同时显示 CNN 结果 |

KEY4 长按用于降速，松开不切换模式。KEY1 允许运行，KEY2 停车，KEY3 作为外部障碍停车输入。方向识别连续确认后才触发定时转向；视觉结果或 STM32 反馈超时会发送零速度并解除运行许可。

FPGA 与 STM32 使用 3.3V TTL 连接：FPGA `C18` 接 STM32 `PD9`，FPGA `D15` 接 STM32 `PD8`，双方共地。STM32 工程位于 `stm32/WHEELTEC_C50X_FPGA_PD89/USER/WHEELTEC.uvprojx`，选择 `4WD_Car` 配置。首次联调应架空车轮，并先确认反馈有效、停车标志清除后再按 KEY1。

## 去雾接口和参数

去雾模块 `user_source/hdl_source/ip/image/dehaze_stream_96.v` 接收 96 位四像素 RGB888 流，连续有效时每时钟处理四个像素，流水线延迟为 11 级。当前参数为大气光 `A=240`、暗通道权重 `218/256`、最小透射率 `64/256`，增益采用 1/64 步进，恢复混合系数为 `40/64`，上限为 `48/64`。

模块使用两行暗通道缓存，720p 合计 5120 bit；颜色恢复乘法两两打包，共用 6 个 DSP。去雾结果直接进入处理图 DDR 和 HAZ 显示路径，方向识别仍读取去雾前的 AWB RGB，避免显示模式影响控制输入。

## 构建和离线验证

在仓库根目录执行：

```powershell
python sim/generate_dehaze_gain_lut.py
python sim/run_dehaze_reference.py
python sim/check_dehaze_packing.py
./sim/run_member2_rtl.ps1
./sim/run_member2_integration.ps1
./scripts/run_td_verify.ps1 -Physical
```

图片验证使用 `sim/run_dehaze_image_v4_clean.ps1`，它为每个输入创建独立的 XSim 构建目录，并输出原图、旁路图、去雾图和对比图：

```powershell
./sim/run_dehaze_image_v4_clean.ps1 `
  -InputImage E:\FPGA\workspace\Fog_3.png `
  -OutputDir E:\FPGA\workspace\anlu\reports\fog_1_5_20261013_v4\Fog_3
```

`reports/fog_1_5_20261013_v4/` 保存五张实图的 RTL 输出和对比图；每张图均检查原图旁路及逐通道参考一致性。完整算法接口见 `user_source/hdl_source/ip/image/dehaze_stream_96_spec.md`。

## 验证边界

XSim 验证覆盖连续视频流、帧边界、模式锁存、原图旁路、双图 DDR 写入和五张实图。TD 用于安路综合和物理实现，不能把 XSim 结果当作板级验证。当前资料没有替代真实摄像头、HDMI 接收端、STM32 电机和赛道环境的实测；下载 bitstream 前必须以当前源码重新完成 TD 综合、布局布线、时序和 bitgen。
