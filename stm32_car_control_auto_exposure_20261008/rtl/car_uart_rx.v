`timescale 1ns/1ps
// Synthesizable UART receiver, 8N1, with a two-flop input synchronizer.
// valid and framing_error are one-clock pulses. A framing error never emits valid.
module car_uart_rx #(
    parameter integer CLK_HZ = 50000000,
    parameter integer BAUD = 115200
) (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx,
    output reg  [7:0] data,
    output reg        valid,
    output reg        framing_error
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
    localparam integer HALF_TICKS = BIT_TICKS / 2;
    localparam integer TIMER_WIDTH = counter_width(BIT_TICKS);
    localparam [1:0] IDLE = 2'd0, START = 2'd1, DATA = 2'd2, STOP = 2'd3;

    // These registers are the only consumers of the asynchronous pin.
    (* ASYNC_REG = "TRUE" *) reg rx_meta;
    (* ASYNC_REG = "TRUE" *) reg rx_sync;
    reg [1:0] state;
    reg [TIMER_WIDTH-1:0] bit_timer;
    reg [2:0] bit_index;
    reg [7:0] shift_data;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rx_meta <= 1'b1;
            rx_sync <= 1'b1;
        end else begin
            rx_meta <= rx;
            rx_sync <= rx_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= IDLE;
            bit_timer <= 0;
            bit_index <= 0;
            shift_data <= 0;
            data <= 0;
            valid <= 1'b0;
            framing_error <= 1'b0;
        end else begin
            valid <= 1'b0;
            framing_error <= 1'b0;
            case (state)
                IDLE: begin
                    if (!rx_sync) begin
                        // Re-check at the center of the start bit to reject glitches.
                        bit_timer <= HALF_TICKS - 1;
                        state <= START;
                    end
                end
                START: begin
                    if (bit_timer != 0)
                        bit_timer <= bit_timer - 1'b1;
                    else if (rx_sync)
                        state <= IDLE;
                    else begin
                        bit_timer <= BIT_TICKS - 1;
                        bit_index <= 0;
                        state <= DATA;
                    end
                end
                DATA: begin
                    if (bit_timer != 0)
                        bit_timer <= bit_timer - 1'b1;
                    else begin
                        shift_data[bit_index] <= rx_sync;
                        bit_timer <= BIT_TICKS - 1;
                        if (bit_index == 7)
                            state <= STOP;
                        else
                            bit_index <= bit_index + 1'b1;
                    end
                end
                STOP: begin
                    if (bit_timer != 0)
                        bit_timer <= bit_timer - 1'b1;
                    else begin
                        if (rx_sync) begin
                            data <= shift_data;
                            valid <= 1'b1;
                        end else begin
                            framing_error <= 1'b1;
                        end
                        state <= IDLE;
                    end
                end
                default: state <= IDLE;
            endcase
        end
    end
endmodule
