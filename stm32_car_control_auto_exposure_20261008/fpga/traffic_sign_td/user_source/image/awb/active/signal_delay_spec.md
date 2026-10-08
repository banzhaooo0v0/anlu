# signal_delay

## 功能

模块通过 RAM A 端口写入 96 位像素数据，并通过 B 端口读取延迟数据。

## B 端口约束

`web` 固定为 `1'b0`，`dib` 固定为 `96'd0`。因此 B 端口只读，不会写入 RAM。

```wavedrom
{signal:[
  {name:'I_valid',wave:'01010'},
  {name:'wea',wave:'01010'},
  {name:'web',wave:'0....'},
  {name:'dib',wave:'x....',data:['0']}
]}
```

## 验证

TD 综合不得再报告该 RAM B 端口的 `dib` 未连接告警。
