`timescale 1ns/1ps
// WHEELTEC C50X 24-byte telemetry receiver.
// 0:7B, 1:flag, 2..7:signed velocity, 8..13:accel, 14..19:gyro,
// 20..21:battery in mV, 22:XOR(bytes 0..21), 23:7D. All words are big endian.
// A sliding window recovers from garbage and dropped bytes. Payload 7B/7D bytes
// never reset reception. Outputs update atomically only after complete validation.
module car_telemetry_rx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
) (
    input  wire               clk,
    input  wire               rst_n,
    input  wire               rx,
    output reg                status_valid,
    output reg  [7:0]         flag_stop,
    output reg signed [15:0]  vx,
    output reg signed [15:0]  vy,
    output reg signed [15:0]  wz,
    output reg signed [15:0]  accel_x,
    output reg signed [15:0]  accel_y,
    output reg signed [15:0]  accel_z,
    output reg signed [15:0]  gyro_x,
    output reg signed [15:0]  gyro_y,
    output reg signed [15:0]  gyro_z,
    output reg  [15:0]        battery_mv,
    output reg  [31:0]        valid_count,
    output reg  [31:0]        error_count,
    output reg                uart_error
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

    localparam integer RAW_TICKS = (CLK_HZ + BAUD / 2) / BAUD;
    localparam integer BIT_TICKS = (RAW_TICKS < 2) ? 2 : RAW_TICKS;
    // Four UART character times: clear an incomplete frame after a long byte gap.
    localparam integer GAP_TICKS = BIT_TICKS * 40;
    localparam integer GAP_WIDTH = counter_width(GAP_TICKS);

    wire [7:0] uart_data;
    wire uart_valid;
    wire uart_framing_error;
    reg [7:0] rx_window [0:23];
    reg [4:0] fill_count;
    reg [GAP_WIDTH-1:0] gap_timer;
    reg [7:0] candidate_bcc;
    integer i;
    integer j;

    car_uart_rx #(.CLK_HZ(CLK_HZ), .BAUD(BAUD)) u_rx (
        .clk(clk), .rst_n(rst_n), .rx(rx), .data(uart_data),
        .valid(uart_valid), .framing_error(uart_framing_error)
    );

    // After shifting, the candidate is old window[1..23] followed by uart_data.
    // Thus bytes 0..21 are old window[1..22], BCC is old window[23].
    always @* begin
        candidate_bcc = 0;
        for (j = 1; j <= 22; j = j + 1)
            candidate_bcc = candidate_bcc ^ rx_window[j];
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            status_valid <= 1'b0;
            flag_stop <= 0;
            vx <= 0;
            vy <= 0;
            wz <= 0;
            accel_x <= 0;
            accel_y <= 0;
            accel_z <= 0;
            gyro_x <= 0;
            gyro_y <= 0;
            gyro_z <= 0;
            battery_mv <= 0;
            valid_count <= 0;
            error_count <= 0;
            uart_error <= 1'b0;
            fill_count <= 0;
            gap_timer <= 0;
            for (i = 0; i < 24; i = i + 1)
                rx_window[i] <= 0;
        end else begin
            status_valid <= 1'b0;
            uart_error <= uart_framing_error;

            if (uart_framing_error) begin
                // The damaged byte makes the accumulated candidate incomplete.
                fill_count <= 0;
                gap_timer <= 0;
                error_count <= error_count + 1'b1;
            end else if (uart_valid) begin
                gap_timer <= 0;
                for (i = 0; i < 23; i = i + 1)
                    rx_window[i] <= rx_window[i+1];
                rx_window[23] <= uart_data;

                if (fill_count < 24)
                    fill_count <= fill_count + 1'b1;

                if (fill_count >= 23 && rx_window[1] == 8'h7b) begin
                    if (uart_data == 8'h7d && candidate_bcc == rx_window[23]) begin
                        flag_stop <= rx_window[2];
                        vx <= {rx_window[3], rx_window[4]};
                        vy <= {rx_window[5], rx_window[6]};
                        wz <= {rx_window[7], rx_window[8]};
                        accel_x <= {rx_window[9], rx_window[10]};
                        accel_y <= {rx_window[11], rx_window[12]};
                        accel_z <= {rx_window[13], rx_window[14]};
                        gyro_x <= {rx_window[15], rx_window[16]};
                        gyro_y <= {rx_window[17], rx_window[18]};
                        gyro_z <= {rx_window[19], rx_window[20]};
                        battery_mv <= {rx_window[21], rx_window[22]};
                        status_valid <= 1'b1;
                        valid_count <= valid_count + 1'b1;
                        // A valid frame ends here; skip overlapping payload candidates.
                        fill_count <= 0;
                    end else begin
                        error_count <= error_count + 1'b1;
                    end
                end
            end else if (fill_count != 0) begin
                if (gap_timer == GAP_TICKS - 1) begin
                    fill_count <= 0;
                    gap_timer <= 0;
                end else begin
                    gap_timer <= gap_timer + 1'b1;
                end
            end else begin
                gap_timer <= 0;
            end
        end
    end
endmodule
