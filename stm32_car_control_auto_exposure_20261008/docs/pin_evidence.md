# 接线依据

1. FPGA 手册：`D:/qrsfpga/qrsfpga/HX1P35A_Contest_202606/9_康芯开发板使用手册及实验平台/新HX1P35A开发板手册-HDL版2604.pdf`。
   - PDF 第7页：J1 1(GPIOA_0)=C18、2(GPIOA_1)=D15、12/30=GND；11=5V、29=3.3V，不用于跨接本包串口。
   - PDF 第22–23页：KEY1=D5、KEY2=A9、KEY3=B9、KEY4=C7，按下为低电平。
2. STM32 原理图：`D:/qrsfpga/car/2.WHEELTEC R550 PLUS ROS大型科研机器人系列资料/4.芯片数据手册与原理图/主控制器_C50C版/原理图与资源分配图/V2.0版/C50C-V2.0原理图.pdf`。
   - HDR2：PD9=15、PD8=16、GND=4/19/20。
   - STM32F407 USART3 AF7：PD8=TX、PD9=RX；实际源码 `HARDWARE/Inc/uartx.h` 已选择这组。
3. 协议依据：原厂 `HARDWARE/uartx.c` 的 `USART3_IRQHandler` 与 `BALANCE/data_task.c` 的 `data_task`；精确更改及编译器检查见 `stm32/README.md`。

FPGA J1 与小车 HDR2 不同排针，针号不相同；TX/RX交叉连。连接器方向以实物1脚标记/方形焊盘及图纸为准。未用万用表实测用户板子的针脚，也未实测实际车轮方向。
