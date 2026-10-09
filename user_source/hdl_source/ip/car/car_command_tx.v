`timescale 1ns/1ps
// WHEELTEC C50X serial command sender.
// Units: cmd_vx/cmd_vy are mm/s; cmd_wz is 0.001 rad/s, all signed 16-bit.
// Frame: 7B 00 00 vx_hi vx_lo vy_hi vy_lo wz_hi wz_lo BCC 7D.
// BCC is XOR of bytes 0..8. Command values are captured once per whole frame.
module car_command_tx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200,
    parameter integer SEND_HZ = 50
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               force_zero,
    input  wire signed [15:0] cmd_vx,
    input  wire signed [15:0] cmd_vy,
    input  wire signed [15:0] cmd_wz,
    output wire               tx,
    output reg                frame_sent,
    output reg  [31:0]        frame_count
);
    function integer counter_width;
        input integer value;
        integer v;
        begin
            v = value - 1;
            counter_width = 0;
            while (v > 0) begin
                counter_width = counter_width + 1;
                v = v >> 1;
            end
            if (counter_width < 1)
                counter_width = 1;
        end
    endfunction

    localparam integer RAW_PERIOD = (CLK_HZ + SEND_HZ / 2) / SEND_HZ;
    localparam integer PERIOD_TICKS = (RAW_PERIOD < 2) ? 2 : RAW_PERIOD;
    localparam integer PERIOD_WIDTH = counter_width(PERIOD_TICKS);
    localparam [1:0] IDLE = 2'd0, SEND_BYTES = 2'd1, WAIT_LAST = 2'd2;

    reg [PERIOD_WIDTH-1:0] period_timer;
    reg period_due;
    reg force_zero_prev;
    reg stop_pending;
    reg [1:0] state;
    reg [7:0] frame [0:10];
    reg [3:0] byte_index;
    reg [7:0] uart_data;
    reg uart_valid;
    wire uart_ready;
    wire force_zero_rise = force_zero && !force_zero_prev;
    integer i;

    car_uart_tx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_tx (
        .clk(clk), .rst_n(rst_n), .data(uart_data), .valid(uart_valid),
        .ready(uart_ready), .tx(tx)
    );

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_timer <= 0;
            period_due <= 1'b1; // Send the first frame without waiting one period.
            force_zero_prev <= 1'b0;
            stop_pending <= 1'b0;
            state <= IDLE;
            byte_index <= 0;
            uart_data <= 0;
            uart_valid <= 1'b0;
            frame_sent <= 1'b0;
            frame_count <= 0;
            for (i = 0; i < 11; i = i + 1)
                frame[i] <= 0;
        end else begin
            frame_sent <= 1'b0;
            force_zero_prev <= force_zero;

            if (period_timer == PERIOD_TICKS - 1) begin
                period_timer <= 0;
                period_due <= 1'b1;
            end else begin
                period_timer <= period_timer + 1'b1;
            end

            // Preserve even a one-cycle stop request while an atomic frame is sent.
            if (force_zero_rise)
                stop_pending <= 1'b1;

            case (state)
                IDLE: begin
                    uart_valid <= 1'b0;
                    if (period_due || stop_pending || force_zero_rise) begin
                        frame[0] <= 8'h7b;
                        frame[1] <= 8'h00;
                        frame[2] <= 8'h00;
                        frame[10] <= 8'h7d;
                        if (force_zero || stop_pending || force_zero_rise) begin
                            frame[3] <= 0;
                            frame[4] <= 0;
                            frame[5] <= 0;
                            frame[6] <= 0;
                            frame[7] <= 0;
                            frame[8] <= 0;
                            frame[9] <= 8'h7b;
                        end else begin
                            frame[3] <= cmd_vx[15:8];
                            frame[4] <= cmd_vx[7:0];
                            frame[5] <= cmd_vy[15:8];
                            frame[6] <= cmd_vy[7:0];
                            frame[7] <= cmd_wz[15:8];
                            frame[8] <= cmd_wz[7:0];
                            frame[9] <= 8'h7b ^ cmd_vx[15:8] ^ cmd_vx[7:0]
                                              ^ cmd_vy[15:8] ^ cmd_vy[7:0]
                                              ^ cmd_wz[15:8] ^ cmd_wz[7:0];
                        end
                        byte_index <= 0;
                        period_timer <= 0;
                        period_due <= 1'b0;
                        stop_pending <= 1'b0;
                        state <= SEND_BYTES;
                    end
                end
                SEND_BYTES: begin
                    if (!uart_valid && uart_ready) begin
                        uart_data <= frame[byte_index];
                        uart_valid <= 1'b1;
                    end else if (uart_valid && uart_ready) begin
                        uart_valid <= 1'b0;
                        if (byte_index == 10)
                            state <= WAIT_LAST;
                        else
                            byte_index <= byte_index + 1'b1;
                    end
                end
                WAIT_LAST: begin
                    if (uart_ready) begin
                        frame_sent <= 1'b1;
                        frame_count <= frame_count + 1'b1;
                        state <= IDLE;
                    end
                end
                default: begin
                    state <= IDLE;
                    uart_valid <= 1'b0;
                end
            endcase
        end
    end
endmodule
