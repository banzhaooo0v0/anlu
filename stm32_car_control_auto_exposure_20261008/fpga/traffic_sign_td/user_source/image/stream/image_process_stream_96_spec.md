# image_process_stream_96

## 功能

模块处理每拍四个 RGB888 像素。帧首有效拍锁存算法模式和 Sobel 阈值。当前帧的所有有效拍使用该锁存值。

两行灰度缓存和两行 Sobel 缓存不使用复位。行号保护逻辑在当前帧写入所需行前输出零，因此复位后首帧不会读取旧缓存。该结构允许 TD 将行缓存推断为存储器，不把 18 Kbit 行缓存实现为可异步复位的触发器。

## 接口和时序

- `I_clk` 为工作时钟，`I_rst_n` 为低有效异步复位。
- `I_tuser && I_tvalid` 标记帧首。灰度级先寄存该拍的 RGB、灰度、模式和阈值；窗口级锁存 3x3 灰度窗口；Sobel 级计算边缘；形态学级输出结果。
- 输出相对输入固定延迟三拍。帧首、行尾、有效和灰度模式随数据一起延迟。
- 帧首对应的灰度级使用输入模式和阈值，并将它们锁存。非帧首有效拍使用锁存模式和阈值。`O_gray_mode` 与 `O_tdata` 的算法选择一致。

```wavedrom
{signal:[
  {name:'I_tvalid',wave:'0111111'},
  {name:'I_tuser', wave:'0100000'},
  {name:'gray_stage_valid',wave:'0011111'},
  {name:'window_stage_valid',wave:'0001111'},
  {name:'sobel_stage_valid',wave:'0000111'},
  {name:'O_gray_tvalid',wave:'0000111'},
  {name:'O_gray_tuser',wave:'0000100'}
]}
```

## 验证

复位后检查 RAW 默认模式；在帧中间改变 `I_algo_mode`，确认本帧输出不变；在下一帧首拍改变模式，确认新帧在三拍延迟后使用新模式。覆盖 RAW、腐蚀和膨胀。
