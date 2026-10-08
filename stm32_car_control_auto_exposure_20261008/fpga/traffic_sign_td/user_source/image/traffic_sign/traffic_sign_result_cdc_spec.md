# traffic_sign_result_cdc

## 功能

此模块将路牌识别器的稳定 ASCII 结果和事件翻转信号从源时钟域传送到 HDMI 时钟域。它不执行 CNN 推理。

## 接口

| 端口 | 方向 | 时钟域 | 说明 |
|---|---|---|---|
| `I_src_clk` | 输入 | 源域 | 路牌识别结果时钟。 |
| `I_src_rst_n` | 输入 | 源域 | 低有效异步复位。 |
| `I_src_toggle` | 输入 | 源域 | 新结果时翻转。 |
| `I_src_ascii[7:0]` | 输入 | 源域 | 稳定的识别结果。 |
| `I_dst_clk` | 输入 | 目标域 | HDMI 像素时钟。 |
| `I_dst_rst_n` | 输入 | 目标域 | 低有效异步复位。 |
| `O_dst_toggle` | 输出 | 目标域 | 已接收的结果翻转值。 |
| `O_dst_ascii[7:0]` | 输出 | 目标域 | 已同步的 ASCII 结果。 |
| `O_dst_valid` | 输出 | 目标域 | 新结果有效脉冲，持续一个目标时钟。 |

## 时序

源域在 `I_src_toggle` 改变时锁存 `I_src_ascii`。目标域使用两级同步检测翻转，再等待一个目标时钟后输出稳定数据。

```wavedrom
{signal:[
  {name:'I_src_toggle',wave:'0..1....'},
  {name:'I_src_ascii',wave:'x..3....',data:['L']},
  {name:'O_dst_valid',wave:'0.....10'},
  {name:'O_dst_ascii',wave:'x......3',data:['L']}
]}
```

## 验证

`D:/anlu/rtl/sim/traffic_sign/tb_traffic_sign_result_cdc.sv` 发送两个翻转事件，并检查目标域的 ASCII、翻转值和有效脉冲。
