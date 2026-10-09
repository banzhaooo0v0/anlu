# Fog.png 真实图片 RTL 去雾仿真

日期：2026-10-08。输入：`E:\FPGA\workspace\Fog.png`。

## 结果

- `Fog_source.png`：输入文件的原样副本。
- `Fog_original_rtl.png`：从 RTL 旁路输出重建的原图，RGB 像素与输入完全相同。
- `Fog_dehazed_rtl.png`：从 XSim 输出数据重建的去雾图，不是 Python 参考模型生成的结果图。
- `Fog_comparison.png` / `Fog_comparison_preview.png`：左侧原图，右侧去雾图。
- `xsim.log`：RTL 仿真日志；`verification.json`：逐通道比较结果及文件 SHA256。

保留原始尺寸 1920×843，没有缩放或裁切；测试台仅将模块尺寸参数设为该图尺寸。工程 RTL、算法参数和 1024×600 顶层配置未修改，本次不生成新 bitstream。

## 仿真与检查

使用 XSim 2019.2，实例化项目现有 `dehaze_stream_96.v`，分别启用去雾和旁路。四像素 RGB888 / 时钟，10 ns 时钟周期，每行附加 8 个无效周期。逐周期检查输出有效、帧首、行末标志及输入采样到输出的 10 周期延迟。

- 有效输出：404,640 组 / 1,618,560 像素。
- 原图旁路：全部像素一致。
- 去雾：4,855,680 个颜色通道与独立二维窗口参考计算一致，差异数为 0。
- 未知值、标志、延迟和输出数量检查：通过。
- 参数：`ATMOSPHERIC_LIGHT=240`、`OMEGA_Q8=218`、`MIN_TRANSMISSION=64`。

Python 用于图片与十六进制数据转换，以及独立参考核对；最终去雾 PNG 取自 Verilog 仿真输出。测试覆盖去雾模块，不包含摄像头、AWB、DDR PHY、显示接口或真实板卡。1920×843 是本次模块仿真参数，不代表当前 1024×600 bitstream 已支持此分辨率。

## 画质观察

树木与雾区的对比度增强，整体亮度降低，但树木周围及渐变区域出现明显的轮廓分层、局部块状过渡。这与当前六档离散增益和组级局部暗通道的近似有关：像素逐位正确并不表示视觉质量已经理想。平均 RGB 值由 179.09 降为 135.29；该数值仅描述亮度变化，不能作为去雾质量评分。没有无雾真值图，因此不报告 PSNR/SSIM 恢复质量。

后续画质优化可优先研究连续或插值增益及透射率平滑，并重新检查 FPGA 资源、时序与真实图片效果。

## 复现

在 `E:\FPGA\workspace\anlu` 中运行：

```powershell
.\sim\run_dehaze_image.ps1 -InputImage 'E:\FPGA\workspace\Fog.png'
```

依赖现有 Vivado/XSim 2019.2、Python 和 Pillow。中间输入、输出十六进制文件位于 `sim/build_fog`；仿真输出与完整过程日志分别保留在本目录和 `reports/rtl_fog_image_20261008.log`。
