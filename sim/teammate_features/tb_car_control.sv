`timescale 1ns/1ps
// Integration test with independent behavioral 8N1 pin-level UART monitor.
module tb_car_control;
    reg clk=0,src_clk=0;
    always #500 clk=~clk; // 1 MHz, matching CLK_HZ.
    always #700 src_clk=~src_clk;
    reg rst_n=0,src_rst_n=0;
    reg [7:0] src_result_ascii="?";
    reg src_result_toggle=0;
    reg arm_n=1,stop_n=1,obstacle_n=1,slow_n=1,rx=1;
    wire tx,armed,link_ok,result_stale,status_valid;
    wire [2:0] state;
    wire signed [15:0] command_vx,command_vy,command_wz,actual_vx,actual_vy,actual_wz;
    wire [7:0] flag_stop;
    wire [15:0] battery_mv;
    wire [31:0] tx_count,rx_count,rx_error_count;
    car_control #(.CLK_HZ(1000000),.BAUD(100000),.SEND_HZ(500),
        .DEBOUNCE_MS(1),.RESULT_TIMEOUT_MS(30),.LINK_TIMEOUT_MS(30),.TURN_MS(20)) dut(.*);
    reg [7:0] feedback[0:23],tx_bytes[0:10],monitor_byte,checksum;
    reg signed [15:0] last_tx_vx,last_tx_vy,last_tx_wz;
    integer frames=0,byte_index=0,checks=0,baseline,k,j;
    reg monitor_enabled=0;
    task tick(input integer n); repeat(n) begin @(posedge clk); #1; end endtask
    task check(input bit condition,input string message);
        checks=checks+1;
        if(!condition) $fatal(1,"control: %s t=%0t armed=%0d state=%0d rx=%0d tx_frames=%0d",message,$time,armed,state,rx_count,frames);
    endtask
    task vision(input [7:0] code);
        @(negedge src_clk); src_result_ascii=code; src_result_toggle=~src_result_toggle;
        tick(20);
    endtask
    task press_arm;
        @(negedge clk); arm_n=0; tick(1050);
        @(negedge clk); arm_n=1; tick(1050);
    endtask
    task send_byte(input [7:0] value);
        @(negedge clk); rx=0; repeat(10) @(negedge clk);
        for(integer b=0;b<8;b=b+1) begin rx=value[b]; repeat(10) @(negedge clk); end
        rx=1; repeat(10) @(negedge clk);
    endtask
    task send_feedback(input [7:0] flag,input bit corrupt);
        for(integer p=0;p<24;p=p+1) feedback[p]=0;
        feedback[0]=8'h7b; feedback[1]=flag;
        feedback[3]=8'd100; feedback[6]=8'hff; feedback[7]=8'h06;
        feedback[8]=8'h7b; feedback[9]=8'h7d; // Valid framing bytes inside payload.
        feedback[20]=8'h5d; feedback[21]=8'hc0; feedback[23]=8'h7d;
        feedback[22]=0;
        for(integer p=0;p<22;p=p+1) feedback[22]=feedback[22]^feedback[p];
        if(corrupt) feedback[22]=feedback[22]^8'h80;
        for(integer p=0;p<24;p=p+1) send_byte(feedback[p]);
        tick(20);
    endtask
    // Verify packet bytes at the wire, not by reading TX module internals.
    initial begin
        wait(rst_n); monitor_enabled=1;
        forever begin
            @(negedge tx); #5000;
            if(tx!==0) $fatal(1,"monitor invalid UART start");
            for(j=0;j<8;j=j+1) begin #10000; monitor_byte[j]=tx; end
            #10000; if(tx!==1) $fatal(1,"monitor invalid UART stop");
            tx_bytes[byte_index]=monitor_byte;
            if(byte_index==10) begin
                if(tx_bytes[0]!==8'h7b || tx_bytes[1]!==0 || tx_bytes[2]!==0 || tx_bytes[10]!==8'h7d)
                    $fatal(1,"invalid command frame envelope");
                checksum=0; for(k=0;k<9;k=k+1) checksum=checksum^tx_bytes[k];
                if(checksum!==tx_bytes[9]) $fatal(1,"command checksum failed");
                last_tx_vx={tx_bytes[3],tx_bytes[4]}; last_tx_vy={tx_bytes[5],tx_bytes[6]};
                last_tx_wz={tx_bytes[7],tx_bytes[8]};
                frames=frames+1; byte_index=0;
            end else byte_index=byte_index+1;
            #5000;
        end
    end
    initial begin
        tick(5); rst_n=1; src_rst_n=1; tick(2500);
        check(frames>=1 && last_tx_vx==0 && last_tx_wz==0 && !armed,"boot emits stop heartbeat");
        send_feedback(0,1);
        check(rx_count==0 && !link_ok,"bad checksum cannot satisfy feedback interlock");
        vision("?"); press_arm(); check(!armed,"manual ARM fails without valid feedback");
        send_feedback(1,0); vision("?"); press_arm();
        check(rx_count==1 && !armed && flag_stop==1,"disabled STM32 feedback blocks ARM");
        send_feedback(0,0); vision("?"); press_arm();
        check(armed && command_vx==100 && actual_vx==100 && actual_wz==-250 && battery_mv==24000,"valid wire telemetry and fresh vision permit manual ARM");
        tick(4000); check(last_tx_vx==100 && last_tx_vy==0 && last_tx_wz==0,"wire command encodes signed big-endian forward speed");
        vision("L"); vision("L"); check(state==1,"distinct vision frames need three votes");
        vision("L"); check(state==2 && command_wz==250,"third camera event enters left turn");
        tick(4000); check(last_tx_vx==50 && last_tx_wz==250,"wire UART emits left command");
        @(negedge clk); stop_n=0; tick(4);
        check(!armed && command_vx==0 && command_wz==0,"synchronized stop input latches disarm");
        tick(3500); check(last_tx_vx==0 && last_tx_wz==0,"urgent stop reaches UART after any current atomic packet");
        stop_n=1; vision("?"); tick(500); check(!armed,"released button does not rearm automatically");
        send_feedback(0,0); vision("?"); press_arm(); check(armed,"new debounced ARM resumes after stop");
        slow_n=0; tick(4); check(state==5 && command_vx==50,"synchronized slow input changes policy");
        tick(4000); check(last_tx_vx==50 && last_tx_wz==0,"wire UART emits slow forward command");
        obstacle_n=0; tick(4); check(!armed && command_vx==0,"obstacle input disarms");
        arm_n=0; tick(1200); // Consume an ARM press while the obstacle is still asserted.
        obstacle_n=1; slow_n=1; send_feedback(0,0); vision("?"); tick(1500);
        check(!armed,"holding ARM through a fault cannot rearm when the fault clears");
        arm_n=1; tick(1050); press_arm();
        check(armed,"release and new manual press rearms after obstacle with fresh feedback");
        // Continue camera events while deliberately withholding STM32 feedback.
        for(integer n=0;n<20;n=n+1) begin vision("?"); tick(2000); end
        check(!link_ok && !armed && command_vx==0 && !result_stale,"feedback timeout independently stops while vision remains fresh");
        baseline=frames; tick(4000);
        check(frames>baseline && last_tx_vx==0 && last_tx_wz==0,"stop heartbeat continues after fault");
        send_feedback(0,0); vision("?"); press_arm(); check(armed,"manual rearm after feedback timeout");
        // Keep feedback valid while deliberately withholding new camera events.
        for(integer n=0;n<13;n=n+1) send_feedback(0,0);
        check(link_ok && result_stale && !armed && command_vx==0,"vision timeout independently stops while telemetry remains fresh");
        tick(4000); check(last_tx_vx==0 && last_tx_wz==0,"vision timeout is visible as a stop packet on UART");
        $display("PASS tb_car_control (%0d checks; %0d complete UART packets)",checks,frames); $finish;
    end
    initial begin #300000000; $fatal(1,"control test timeout"); end
endmodule
