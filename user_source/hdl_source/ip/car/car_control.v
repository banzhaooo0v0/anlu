`timescale 1ns/1ps
// Public integration boundary: camera-result CDC -> decision -> 50 Hz UART,
// plus checksum-validated feedback freshness interlock. Default clock is 50 MHz.
module car_control #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200,
    parameter integer SEND_HZ = 50,
    parameter integer DEBOUNCE_MS = 20,
    parameter integer RESULT_TIMEOUT_MS = 500,
    parameter integer LINK_TIMEOUT_MS = 500,
    parameter integer TURN_MS = 800,
    parameter integer CONFIRM_FRAMES = 3,
    parameter integer CLEAR_FRAMES = 3
) (
    input wire clk, input wire rst_n,
    input wire src_clk, input wire src_rst_n,
    input wire [7:0] src_result_ascii, input wire src_result_toggle,
    input wire arm_n, input wire stop_n, input wire obstacle_n, input wire slow_n,
    input wire rx, output wire tx,
    output wire armed, output wire [2:0] state,
    output wire signed [15:0] command_vx, command_vy, command_wz,
    output wire link_ok, output wire result_stale,
    output wire status_valid, output wire [7:0] flag_stop,
    output wire signed [15:0] actual_vx, actual_vy, actual_wz,
    output wire [15:0] battery_mv,
    output wire [31:0] tx_count, rx_count, rx_error_count
);
    localparam integer LINK_TICKS = (CLK_HZ / 1000) * LINK_TIMEOUT_MS;
    (* ASYNC_REG = "TRUE" *) reg [1:0] reset_sync;
    (* ASYNC_REG = "TRUE" *) reg [1:0] stop_sync, obstacle_sync, slow_sync;
    wire control_rst_n = reset_sync[1];
    always @(posedge clk or negedge rst_n)
        if (!rst_n) reset_sync <= 0; else reset_sync <= {reset_sync[0],1'b1};
    always @(posedge clk or negedge control_rst_n) begin
        if (!control_rst_n) begin
            stop_sync <= 2'b11; obstacle_sync <= 2'b11; slow_sync <= 2'b11;
        end else begin
            stop_sync <= {stop_sync[0],stop_n};
            obstacle_sync <= {obstacle_sync[0],obstacle_n};
            slow_sync <= {slow_sync[0],slow_n};
        end
    end
    wire arm_pulse;
    car_button #(.CLK_HZ(CLK_HZ),.DEBOUNCE_MS(DEBOUNCE_MS)) u_arm (
        .clk(clk),.rst_n(control_rst_n),.button_n(arm_n),.press(arm_pulse));
    wire [7:0] result_ascii;
    wire result_valid;
    car_result_cdc u_result (
        .src_clk(src_clk),.src_rst_n(src_rst_n),
        .src_ascii(src_result_ascii),.src_toggle(src_result_toggle),
        .dst_clk(clk),.dst_rst_n(control_rst_n),
        .dst_ascii(result_ascii),.dst_valid(result_valid));
    car_telemetry_rx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD)) u_feedback (
        .clk(clk),.rst_n(control_rst_n),.rx(rx),.status_valid(status_valid),
        .flag_stop(flag_stop),.vx(actual_vx),.vy(actual_vy),.wz(actual_wz),
        .accel_x(),.accel_y(),.accel_z(),.gyro_x(),.gyro_y(),.gyro_z(),
        .battery_mv(battery_mv),.valid_count(rx_count),.error_count(rx_error_count),.uart_error());
    reg have_feedback;
    reg [31:0] link_age;
    assign link_ok = have_feedback && link_age < LINK_TICKS;
    always @(posedge clk or negedge control_rst_n) begin
        if (!control_rst_n) begin have_feedback <= 0; link_age <= LINK_TICKS; end
        else if (status_valid) begin have_feedback <= 1; link_age <= 0; end
        else if (link_age < LINK_TICKS) link_age <= link_age + 1'b1;
    end
    wire force_zero;
    car_decision #(.CLK_HZ(CLK_HZ),.CONFIRM_FRAMES(CONFIRM_FRAMES),
        .CLEAR_FRAMES(CLEAR_FRAMES),.RESULT_TIMEOUT_MS(RESULT_TIMEOUT_MS),.TURN_MS(TURN_MS)) u_decision (
        .clk(clk),.rst_n(control_rst_n),.arm_pulse(arm_pulse),
        .estop(!stop_sync[1]),.obstacle(!obstacle_sync[1]),.slow(!slow_sync[1]),
        .result_valid(result_valid),.result_ascii(result_ascii),
        .link_ok(link_ok),.flag_stop(flag_stop),.armed(armed),.state(state),
        .cmd_vx(command_vx),.cmd_vy(command_vy),.cmd_wz(command_wz),
        .force_zero(force_zero),.result_stale(result_stale));
    car_command_tx #(.CLK_HZ(CLK_HZ),.BAUD(BAUD),.SEND_HZ(SEND_HZ)) u_command (
        .clk(clk),.rst_n(control_rst_n),.force_zero(force_zero),
        .cmd_vx(command_vx),.cmd_vy(command_vy),.cmd_wz(command_wz),
        .tx(tx),.frame_sent(),.frame_count(tx_count));
endmodule
