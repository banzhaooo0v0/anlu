# signal_delay

## 功能

模块使用 A 端口写入 96 位像素延迟数据，使用 B 端口读取延迟数据。B 写端口固定禁止写入，写数据固定为零。

## 接口和时序

- `I_clk` 为 A、B 端口共用时钟，`I_rst_n` 为低有效异步复位。
- `I_valid` 驱动 A 端口写使能。
- `web` 固定为 `0`，`dib` 固定为 `96'd0`；因此 B 端口不写入 RAM。

```wavedrom
{signal:[
  {name:'I_valid',wave:'01010'},
  {name:'wea',wave:'01010'},
  {name:'web',wave:'0....'},
  {name:'dib',wave:'x....',data:['0']}
]}
```

## 验证

编译检查 RAM 实例端口全部连接，并确认 B 端口写使能保持为零。
