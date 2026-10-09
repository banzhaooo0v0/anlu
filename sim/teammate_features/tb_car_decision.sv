`timescale 1ns/1ps
module tb_car_decision;
    localparam CLK_HZ=10000, AGE_TICKS=5000, TURN_TICKS=8000;
    reg clk=0; always #50000 clk=~clk; // 10 kHz, matching CLK_HZ.
    reg rst_n=0, arm_pulse=0, estop=0, obstacle=0, slow=0;
    reg result_valid=0, link_ok=0;
    reg [7:0] result_ascii="?", flag_stop=0;
    wire armed, force_zero, result_stale;
    wire [2:0] state;
    wire signed [15:0] vx,vy,wz;
    integer checks=0, i;
    car_decision #(.CLK_HZ(CLK_HZ)) dut (
        .clk(clk),.rst_n(rst_n),.arm_pulse(arm_pulse),.estop(estop),
        .obstacle(obstacle),.slow(slow),.result_valid(result_valid),
        .result_ascii(result_ascii),.link_ok(link_ok),.flag_stop(flag_stop),
        .armed(armed),.state(state),.cmd_vx(vx),.cmd_vy(vy),.cmd_wz(wz),
        .force_zero(force_zero),.result_stale(result_stale));
    task tick(input integer n);
        repeat(n) begin @(posedge clk); #1; end
    endtask
    task check(input bit condition, input string message);
        checks=checks+1;
        if (!condition) $fatal(1,"decision: %s t=%0t state=%0d armed=%0d vx=%0d wz=%0d",message,$time,state,armed,vx,wz);
    endtask
    task fresh(input [7:0] code);
        @(negedge clk); result_ascii=code; result_valid=1;
        tick(1); @(negedge clk); result_valid=0;
    endtask
    task arm;
        @(negedge clk); arm_pulse=1;
        tick(1); @(negedge clk); arm_pulse=0;
    endtask
    task reset;
        @(negedge clk); rst_n=0; arm_pulse=0; estop=0; obstacle=0;
        slow=0; result_valid=0; link_ok=0; flag_stop=0;
        tick(3); @(negedge clk); rst_n=1; tick(3);
    endtask
    task ready_arm;
        link_ok=1; flag_stop=0; fresh("?"); arm();
        check(armed && state==1 && vx==100 && vy==0 && wz==0,"fresh result and healthy link permit manual ARM");
    endtask
    initial begin
        tick(3); rst_n=1; tick(3);
        check(!armed && force_zero && vx==0 && vy==0 && wz==0,"reset must remain stopped");
        link_ok=1; arm();
        check(!armed && result_stale,"no recognition cannot arm");
        fresh("?"); link_ok=0; arm(); check(!armed,"no feedback cannot arm");
        link_ok=1; flag_stop=1; arm(); check(!armed,"STM32 disabled cannot arm");
        flag_stop=0; arm(); check(armed && vx==100,"healthy manual ARM begins low speed forward");

        fresh("L"); fresh("L"); fresh("R"); fresh("L"); fresh("?"); fresh("L"); fresh("L");
        check(state==1 && wz==0,"mixed and unknown frames reset consecutive voting");
        fresh("L"); check(state==2 && vx==50 && wz==250,"third consecutive L enters left turn");
        // Stay on the same sign through the complete 800 ms turn. No restart.
        for(i=1;i<=TURN_TICKS;i=i+1) begin
            result_valid=(i%100==0); result_ascii="L";
            tick(1); @(negedge clk);
            if(i<TURN_TICKS) check(state==2,"turn must not end before its configured duration");
        end
        result_valid=0;
        check(state==1 && wz==0,"repeated L frames do not extend timed turn");
        fresh("L"); fresh("L"); fresh("L"); check(state==1,"held sign cannot retrigger after turn");
        fresh("?"); fresh("?"); fresh("R"); fresh("?"); fresh("?");
        fresh("R"); fresh("R"); fresh("R"); check(state==1,"interrupted clearing does not release sign lock");
        fresh("?"); fresh("?"); fresh("?");
        fresh("R"); fresh("R"); check(state==1,"right vote also needs three frames");
        fresh("R"); check(state==3 && wz==-250,"right turn has negative yaw");

        estop=1; #1; check(vx==0 && vy==0 && wz==0 && force_zero,"ESTOP gates commands without waiting for FSM");
        tick(1); check(!armed && state==0,"ESTOP latches disarm during turn");
        estop=0; fresh("?"); tick(5); check(!armed && vx==0,"releasing ESTOP cannot resume");
        arm(); check(armed,"new ARM resumes after ESTOP");
        obstacle=1; arm_pulse=1; #1; check(vx==0 && wz==0,"obstacle has immediate zero priority");
        tick(1); arm_pulse=0; check(!armed && state==4,"obstacle wins simultaneous ARM");
        obstacle=0; tick(3); check(!armed,"obstacle removal cannot resume");
        fresh("?"); arm(); check(armed,"new ARM resumes after obstacle");
        link_ok=0; #1; check(force_zero && vx==0,"feedback timeout gates speed immediately");
        tick(1); check(!armed && state==6,"lost feedback disarms");
        link_ok=1; tick(3); check(!armed,"feedback recovery alone cannot resume");
        fresh("?"); arm(); flag_stop=1; #1; check(vx==0,"STM32 stop flag gates speed");
        tick(1); check(!armed,"STM32 stop flag disarms");
        flag_stop=0; fresh("?"); arm(); slow=1; tick(1);
        check(state==5 && vx==50 && wz==0,"SLOW input selects low forward speed");
        slow=0; tick(1); check(state==1 && vx==100,"SLOW release restores forward policy");

        reset(); ready_arm(); fresh("?");
        tick(AGE_TICKS-1); check(!result_stale && armed && vx==100,"freshness stays valid until configured timeout");
        tick(1); check(result_stale && force_zero && vx==0,"vision timeout immediately zeros commands");
        tick(1); check(!armed && state==6,"vision timeout latches disarm");
        fresh("?"); tick(3); check(!armed,"vision recovery alone cannot resume");
        arm(); check(armed,"new ARM resumes after fresh recognition");
        $display("PASS tb_car_decision (%0d checks)",checks); $finish;
    end
    initial begin #(64'd10000000000); $fatal(1,"decision test timeout"); end
endmodule
