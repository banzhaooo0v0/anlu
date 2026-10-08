# 小车控制 RTL 独立验证

验证日期：2026-10-04。工具：本机 Vivado Simulator / Xsim 2019.2。

这些是有 `$fatal` 失败断言的自检仿真，不依赖人工观察波形。使用降低后的 `CLK_HZ` 加速事件数量；测试时钟周期与参数一致，UART 输入和独立输出监视器也按该参数的真实波特率生成、采样。

| 测试 | 实际结果 | 覆盖内容 |
| --- | --- | --- |
| `tb_car_decision.sv` | `PASS tb_car_decision (8032 checks)` | 默认零速；新鲜识别、有效反馈与手动 ARM 条件；三帧连续 L/R、交错/未知帧清票；800 ms 转向时间边界；连续识别不延长转向；转后必须连续三帧 `?` 才能重新触发；急停/障碍优先与锁存；link / stop flag / vision timeout 独立停车；恢复必须再次 ARM；SLOW 速度 |
| `tb_car_result_cdc.sv` | `PASS tb_car_result_cdc (11 checks)` | 14 ns 源周期与 50 ns 目标周期异步传输；每事件一次；未切换 toggle 的数据不能发布；busy 保留第一个已提交事件与最新待传事件；字节不撕裂；任一端单独复位时，保持为 1 的旧 toggle 不重放；复位后新事件仍能传递 |
| `tb_car_control.sv` | `PASS tb_car_control (23 checks; 66 complete UART packets)` | 完整 control wrapper；真实 24 字节 UART 反馈含内部 7B/7D，坏 BCC 无法解锁；stop flag；异步摄像头事件；ARM 去抖；独立行为 UART 监视器逐字节检查 66 个指令帧的帧头/尾、保留字节、XOR、速度符号/字节序；前进/左转/减速/停车；故障期间保持 ARM 不会在恢复时自动启动；视觉继续而反馈超时、反馈继续而视觉超时两种独立故障 |

独立评审发现并交由主实现修复的 CDC 问题：复位后 `seen` 固定为 0 会把保持为 1 的旧 toggle 当成新事件。修复为在源复位同步释放阶段跟随当前 `src_toggle` 建立基线。上述单侧复位测试覆盖此修复。

实际原始日志位于本次工作目录 `sim/work_control/decision_xsim.log`、`cdc_xsim.log` 和 `control_xsim.log`。复跑时应同时验证进程状态与 `PASS tb_car_*` 日志标记，并拒绝 `Fatal` / `ERROR`；不能仅凭 Xsim shell 返回码断言通过。

此报告只证明这里列出的数字逻辑和协议场景通过仿真。未证明外部电气连线、FPGA 整体布局布线时序、真实电机方向/转向角度或实车制动距离。当前转向策略为定时速度指令，STM32 原有轮速闭环保留；上游 `?` 仍同时代表未识别/无目标，不能据此声称已经具备视觉避障。
