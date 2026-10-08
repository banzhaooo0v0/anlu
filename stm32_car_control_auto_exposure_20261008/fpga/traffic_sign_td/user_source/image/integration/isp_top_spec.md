# isp_top

## 功能

模块连接官方 Demosaic、AWB、实时图像算法、传统路牌识别和 96 位转 128 位打包器。

AWB 到 `image_process_stream_96` 和 `traffic_sign_detector_96` 之间有一个共享寄存器级。该级在每个时钟采样 AWB 的数据、有效、帧首、行尾和算法模式。它把 AWB 乘法逻辑与图像算法、路牌识别逻辑分成两个时钟周期。图像算法输出、HDMI 视频输出和路牌识别结果相对 AWB 增加一个时钟周期延迟。

## 复位和时序

- `I_rst_n` 是低有效异步复位。
- 复位后寄存器级输出无效，模式默认 RAW。
- `process_stage_tuser` 与 `process_stage_tdata`、`process_stage_tvalid` 同拍对齐。
- 当 AWB 的帧首早于有效数据时，`awb_frame_pending` 将帧首保持到第一个有效数据拍。

```wavedrom
{signal:[
  {name:'awb_O_tvalid',wave:'01010'},
  {name:'awb_O_tuser', wave:'01000'},
  {name:'stage_tvalid',wave:'00101'},
  {name:'stage_tuser', wave:'00100'},
  {name:'process output',wave:'00101'}
]}
```

## 验证

- RTL 综合必须检查 AWB 到图像算法的最差路径已在 `process_stage_*` 寄存器结束。
- 图像算法小尺寸参考模型和 1024×600 全尺寸吞吐量 testbench 必须通过。
- 仍需运行 TD 布局、布线和最终时序分析。
