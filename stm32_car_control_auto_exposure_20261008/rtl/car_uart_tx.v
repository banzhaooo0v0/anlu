`timescale 1ns/1ps
// Synthesizable UART transmitter, 8 data bits, no parity, 1 stop bit.
// data is accepted on a rising clock edge when valid && ready is true.
// CLK_HZ must be at least 2 * BAUD. Baud-rate error is set by integer rounding.
module car_uart_tx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [7:0] data,
    input  wire       valid,
    output wire       ready,
    output wire       tx
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
    localparam integer TIMER_WIDTH = counter_width(BIT_TICKS);

    reg [TIMER_WIDTH-1:0] bit_timer;
    reg [9:0] shift_data;
    reg [3:0] bit_index;
    reg busy;
    reg tx_reg;

    assign ready = !busy;
    assign tx = tx_reg;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bit_timer <= 0;
            shift_data <= 10'h3ff;
            bit_index <= 0;
            busy <= 1'b0;
            tx_reg <= 1'b1;
        end else if (!busy) begin
            tx_reg <= 1'b1;
            if (valid) begin
                // Bit 0 is the start bit; UART sends the least-significant bit first.
                shift_data <= {1'b1, data, 1'b0};
                bit_index <= 0;
                bit_timer <= BIT_TICKS - 1;
                busy <= 1'b1;
                tx_reg <= 1'b0;
            end
        end else if (bit_timer != 0) begin
            bit_timer <= bit_timer - 1'b1;
        end else if (bit_index == 9) begin
            // The complete stop bit has elapsed before ready is asserted.
            busy <= 1'b0;
            tx_reg <= 1'b1;
        end else begin
            bit_timer <= BIT_TICKS - 1;
            shift_data <= {1'b1, shift_data[9:1]};
            bit_index <= bit_index + 1'b1;
            tx_reg <= shift_data[1];
        end
    end
endmodule
