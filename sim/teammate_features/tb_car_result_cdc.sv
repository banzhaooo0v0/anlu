`timescale 1ns/1ps
module tb_car_result_cdc;
    reg src_clk=0,dst_clk=0;
    always #7 src_clk=~src_clk;
    always #25 dst_clk=~dst_clk;
    reg src_rst_n=0,dst_rst_n=0,src_toggle=0;
    reg [7:0] src_ascii="?";
    wire [7:0] dst_ascii;
    wire dst_valid;
    reg [7:0] received[0:31];
    integer count=0,checks=0,baseline,i;
    car_result_cdc dut(.*);
    always @(posedge dst_clk) begin
        #1;
        if(dst_valid) begin
            if(count>=32) $fatal(1,"CDC duplicate/overflow");
            received[count]=dst_ascii; count=count+1;
        end
    end
    task wait_src(input integer n); repeat(n) begin @(posedge src_clk); #1; end endtask
    task wait_dst(input integer n); repeat(n) begin @(posedge dst_clk); #2; end endtask
    task check(input bit condition,input string message);
        checks=checks+1; if(!condition) $fatal(1,"CDC: %s count=%0d t=%0t",message,count,$time);
    endtask
    task emit(input [7:0] value);
        @(negedge src_clk); src_ascii=value; src_toggle=~src_toggle;
        wait_src(1);
    endtask
    initial begin
        wait_src(3); src_rst_n=1; dst_rst_n=1; wait_src(6); wait_dst(3);
        check(count==0,"reset must not manufacture an event");
        emit("L"); wait_dst(12);
        check(count==1 && received[0]=="L","one left event crosses asynchronous clocks once");
        // Change unrelated source data without a toggle: destination must retain its event.
        src_ascii=8'ha5; wait_dst(8); check(count==1,"untoggled source data cannot publish");
        emit("R"); wait_dst(12); check(count==2 && received[1]=="R","next event is captured without byte tearing");
        // Keep first bundled byte stable while waiting for slow destination ACK.
        baseline=count;
        emit(8'h55); emit(8'h33); emit(8'hcc); emit(8'haa);
        wait_dst(20);
        check(count==baseline+2,"busy mailbox emits first event and the latest pending event only");
        check(received[baseline]==8'h55 && received[baseline+1]==8'haa,"pending replacement retains coherent latest byte");
        wait_dst(12); check(count==baseline+2,"ACK completion cannot duplicate latest event");
        // Force toggle=1 (old L), then reset only destination. This is not a new event.
        if(!src_toggle) begin emit("L"); wait_dst(12); end
        baseline=count;
        @(negedge dst_clk); dst_rst_n=0; wait_dst(3);
        dst_rst_n=1; wait_src(8); wait_dst(12);
        check(count==baseline,"destination-only reset must not replay held toggle=1");
        emit("R"); wait_dst(12);
        check(count==baseline+1 && received[baseline]=="R","fresh event works after destination reset");
        if(!src_toggle) begin emit("L"); wait_dst(12); end
        baseline=count;
        @(negedge src_clk); src_rst_n=0; wait_src(3); src_rst_n=1;
        wait_src(8); wait_dst(12);
        check(count==baseline,"source-only reset must not replay held toggle=1");
        emit("?"); wait_dst(12);
        check(count==baseline+1 && received[baseline]=="?","fresh event works after source reset");
        $display("PASS tb_car_result_cdc (%0d checks)",checks); $finish;
    end
    initial begin #100000; $fatal(1,"CDC test timeout"); end
endmodule
