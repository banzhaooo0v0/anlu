`timescale 1ns/1ps
// Self-checking serial-level simulation. No vendor IP is required.
// 1 MHz / 100 kbaud keeps runtime short without changing the frame protocol.
module tb_car_uart;
    localparam integer CLK_HZ = 1000000;
    localparam integer BAUD = 100000;
    localparam integer BIT_TICKS = CLK_HZ / BAUD;
    reg clk = 0;
    always #500 clk = ~clk;
    reg rst_n = 0;
    reg force_zero = 0;
    reg signed [15:0] cmd_vx = 16'sd100;
    reg signed [15:0] cmd_vy = -16'sd200;
    reg signed [15:0] cmd_wz = 16'sd300;
    wire command_tx;
    wire frame_sent;
    wire [31:0] frame_count;
    reg telemetry_rx = 1;
    wire status_valid;
    wire [7:0] flag_stop;
    wire signed [15:0] vx, vy, wz, accel_x, accel_y, accel_z;
    wire signed [15:0] gyro_x, gyro_y, gyro_z;
    wire [15:0] battery_mv;
    wire [31:0] valid_count, error_count;
    wire uart_error;

    car_command_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD), .SEND_HZ(50)) command_dut (
        .clk(clk), .rst_n(rst_n), .force_zero(force_zero),
        .cmd_vx(cmd_vx), .cmd_vy(cmd_vy), .cmd_wz(cmd_wz),
        .tx(command_tx), .frame_sent(frame_sent), .frame_count(frame_count)
    );
    car_telemetry_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) status_dut (
        .clk(clk), .rst_n(rst_n), .rx(telemetry_rx),
        .status_valid(status_valid), .flag_stop(flag_stop),
        .vx(vx), .vy(vy), .wz(wz), .accel_x(accel_x), .accel_y(accel_y),
        .accel_z(accel_z), .gyro_x(gyro_x), .gyro_y(gyro_y), .gyro_z(gyro_z),
        .battery_mv(battery_mv), .valid_count(valid_count),
        .error_count(error_count), .uart_error(uart_error)
    );

    // Independent behavioral UART decoder; it does not reuse car_uart_rx.
    reg [7:0] command_bytes [0:351];
    time command_start [0:31];
    integer command_byte_count = 0;
    integer bit_i;
    reg [7:0] observed_byte;
    initial begin
        wait (rst_n);
        forever begin
            @(negedge command_tx);
            if ((command_byte_count % 11) == 0)
                command_start[command_byte_count / 11] = $time;
            repeat (BIT_TICKS + BIT_TICKS / 2) @(posedge clk);
            #1;
            observed_byte[0] = command_tx;
            for (bit_i = 1; bit_i < 8; bit_i = bit_i + 1) begin
                repeat (BIT_TICKS) @(posedge clk);
                #1;
                observed_byte[bit_i] = command_tx;
            end
            repeat (BIT_TICKS) @(posedge clk);
            #1;
            if (command_tx !== 1'b1)
                $fatal(1, "UART TX stop bit was not high");
            if (command_byte_count >= 352)
                $fatal(1, "Command capture overflow");
            command_bytes[command_byte_count] = observed_byte;
            command_byte_count = command_byte_count + 1;
        end
    end

    task check_command;
        input integer frame_num;
        input [15:0] ex_vx, ex_vy, ex_wz;
        integer base;
        integer k;
        reg [7:0] bcc;
        begin
            base = frame_num * 11;
            if (command_bytes[base] !== 8'h7b ||
                command_bytes[base+1] !== 0 || command_bytes[base+2] !== 0 ||
                command_bytes[base+10] !== 8'h7d)
                $fatal(1, "Command header/reserved/trailer mismatch in frame %0d", frame_num);
            if ({command_bytes[base+3], command_bytes[base+4]} !== ex_vx ||
                {command_bytes[base+5], command_bytes[base+6]} !== ex_vy ||
                {command_bytes[base+7], command_bytes[base+8]} !== ex_wz)
                $fatal(1, "Command signed-word/snapshot mismatch in frame %0d", frame_num);
            bcc = 0;
            for (k = 0; k < 9; k = k + 1)
                bcc = bcc ^ command_bytes[base+k];
            if (command_bytes[base+9] !== bcc)
                $fatal(1, "Command XOR checksum mismatch in frame %0d", frame_num);
        end
    endtask

    task send_byte;
        input [7:0] value;
        input good_stop;
        integer k;
        begin
            @(negedge clk);
            telemetry_rx = 0;
            repeat (BIT_TICKS) @(negedge clk);
            for (k = 0; k < 8; k = k + 1) begin
                telemetry_rx = value[k];
                repeat (BIT_TICKS) @(negedge clk);
            end
            telemetry_rx = good_stop;
            repeat (BIT_TICKS) @(negedge clk);
            telemetry_rx = 1;
        end
    endtask

    reg [7:0] status_packet [0:23];
    task send_packet;
        input integer omitted_byte;
        integer k;
        begin
            for (k = 0; k < 24; k = k + 1)
                if (k != omitted_byte)
                    send_byte(status_packet[k], 1);
            repeat (20) @(negedge clk);
        end
    endtask

    task check_status;
        input [31:0] expected_count;
        begin
            if (valid_count !== expected_count)
                $fatal(1, "Telemetry count expected %0d, got %0d", expected_count, valid_count);
            if (flag_stop !== 8'h01 || vx !== 16'sd123 || vy !== -16'sd123 ||
                wz !== 16'sd32002 || accel_x !== -16'sd1000 || accel_y !== 16'sd1000 ||
                accel_z !== 16'h7b7d || gyro_x !== -16'sd2 || gyro_y !== 16'sd3 ||
                gyro_z !== 16'h8000 || battery_mv !== 16'd24000)
                $fatal(1, "Telemetry signed values, units, or byte offsets are wrong");
        end
    endtask

    reg status_valid_prev = 0;
    reg frame_sent_prev = 0;
    integer uart_error_pulses = 0;
    always @(posedge clk) begin
        if (rst_n) begin
            if (status_valid && status_valid_prev)
                $fatal(1, "status_valid exceeded one clock");
            if (frame_sent && frame_sent_prev)
                $fatal(1, "frame_sent exceeded one clock");
            if (uart_error)
                uart_error_pulses = uart_error_pulses + 1;
        end
        status_valid_prev <= status_valid;
        frame_sent_prev <= frame_sent;
    end

    integer k;
    reg [7:0] bcc;
    reg [31:0] errors_before;
    initial begin
        status_packet[0] = 8'h7b; status_packet[1] = 8'h01;
        status_packet[2] = 8'h00; status_packet[3] = 8'h7b;
        status_packet[4] = 8'hff; status_packet[5] = 8'h85;
        status_packet[6] = 8'h7d; status_packet[7] = 8'h02;
        status_packet[8] = 8'hfc; status_packet[9] = 8'h18;
        status_packet[10] = 8'h03; status_packet[11] = 8'he8;
        status_packet[12] = 8'h7b; status_packet[13] = 8'h7d;
        status_packet[14] = 8'hff; status_packet[15] = 8'hfe;
        status_packet[16] = 8'h00; status_packet[17] = 8'h03;
        status_packet[18] = 8'h80; status_packet[19] = 8'h00;
        status_packet[20] = 8'h5d; status_packet[21] = 8'hc0;
        bcc = 0;
        for (k = 0; k < 22; k = k + 1)
            bcc = bcc ^ status_packet[k];
        status_packet[22] = bcc;
        status_packet[23] = 8'h7d;

        repeat (10) @(negedge clk);
        rst_n = 1;

        // A command update and stop request during the first packet must not tear it.
        wait (command_byte_count >= 1);
        @(negedge clk);
        cmd_vx = 444; cmd_vy = 555; cmd_wz = 666;
        force_zero = 1;
        wait (command_byte_count >= 22);
        check_command(0, 16'd100, -16'd200, 16'd300);
        check_command(1, 0, 0, 0);
        if ((command_start[1] - command_start[0]) >= 2000000)
            $fatal(1, "Stop packet waited for the 20 ms heartbeat instead of following active packet");
        wait (command_byte_count >= 33);
        check_command(2, 0, 0, 0);
        if ((command_start[2] - command_start[1]) < 19900000 ||
            (command_start[2] - command_start[1]) > 20100000)
            $fatal(1, "Stopped heartbeat is not 50 Hz");
        wait (frame_count >= 3);
        @(negedge clk);
        force_zero = 0;
        cmd_vx = 16'h8000; cmd_vy = 16'h7fff; cmd_wz = -1;
        wait (command_byte_count >= 44);
        check_command(3, 16'h8000, 16'h7fff, 16'hffff);
        wait (frame_count >= 4);

        // Pulse stop for only one clock during an active frame. It must be retained.
        wait (command_byte_count >= 45);
        @(negedge clk); force_zero = 1;
        @(negedge clk); force_zero = 0;
        wait (command_byte_count >= 66);
        check_command(4, 16'h8000, 16'h7fff, 16'hffff);
        check_command(5, 0, 0, 0);
        $display("PASS: signed command fields, XOR, atomic snapshot, urgent stop, zero heartbeat");

        // A sub-half-bit input glitch must not be decoded as a start bit.
        @(negedge clk); telemetry_rx = 0;
        @(negedge clk); telemetry_rx = 1;
        repeat (50) @(negedge clk);
        send_packet(-1);
        check_status(1);
        if (uart_error_pulses != 0)
            $fatal(1, "Short start-bit glitch was not rejected");

        send_byte(8'h12, 1); send_byte(8'h34, 1);
        send_byte(8'h56, 1); send_byte(8'h7d, 1);
        send_packet(-1);
        check_status(2);

        errors_before = error_count;
        status_packet[22] = bcc ^ 8'h01;
        send_packet(-1);
        check_status(2);
        if (error_count <= errors_before)
            $fatal(1, "Bad checksum was not counted");
        status_packet[22] = bcc;

        // Allow the bad window to expire before the next isolated malformed test.
        repeat (500) @(negedge clk);
        errors_before = error_count;
        status_packet[23] = 8'h00;
        send_packet(-1);
        check_status(2);
        if (error_count <= errors_before)
            $fatal(1, "Bad trailer was not counted");
        status_packet[23] = 8'h7d;

        // No idle gap here: a 23-byte damaged frame must resync to the next header.
        send_packet(8);
        check_status(2);
        send_packet(-1);
        check_status(3);

        // A long gap clears partial data; its suffix must not create a valid packet.
        for (k = 0; k < 7; k = k + 1)
            send_byte(status_packet[k], 1);
        repeat (500) @(negedge clk);
        for (k = 7; k < 24; k = k + 1)
            send_byte(status_packet[k], 1);
        repeat (20) @(negedge clk);
        check_status(3);
        send_packet(-1);
        check_status(4);

        errors_before = error_count;
        send_byte(8'h55, 0);
        repeat (50) @(negedge clk);
        if (uart_error_pulses < 1 || error_count <= errors_before)
            $fatal(1, "UART framing error was not reported");
        send_packet(-1);
        check_status(5);
        $display("PASS: telemetry offsets, payload markers, junk, bad BCC, bad tail, byte loss, gap, UART error");
        $display("ALL CAR UART TESTS PASSED");
        $finish;
    end

    initial begin
        #250000000;
        $fatal(1, "Simulation timeout");
    end
endmodule
