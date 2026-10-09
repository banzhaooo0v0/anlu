# 1280×720 整合版 FPGA 产物

`camera_to_dsi_display_720p.bit` 是本次整合版的**未压缩** bitstream，目标 PH1P35MDG324、speed 3，由 TD 6.2.168116 生成。包含去雾、原图/处理图双 DDR 缓存、原 CNN、方向识别、小车串口控制、腐蚀/膨胀及 720p 自动曝光。

最终 Routed 时序：Setup WNS +0.115 ns、Hold WNS +0.020 ns，TNS 均为 0。单线程布线、关闭 bitstream 压缩规避了本机 TD 的内部崩溃。完整证据见 [整合报告](../../reports/integration_20261009.md)。

文件大小 **1,789,539 字节**。SHA-256：

```text
2c78e5af304b519c3cd3006dec3775968d17615cd82f06b580547b872d0831af
```

[manifest.json](manifest.json) 记录产物、脚本及报告哈希；[source_sha256.json](source_sha256.json) 固定本次源码、IP 与工程配置树。可用 PowerShell `Get-FileHash ./camera_to_dsi_display_720p.bit -Algorithm SHA256` 核对。

本次没有连接硬件或执行下载。按 [项目 README](../../README.md) 核对实际板卡、引脚、电平和小车操作；该产物不是 STM32 固件。资源和时序裕量较小，改源码、IP 或约束后必须重新实现，不能把这个 bit 文件当作修改后的版本。
