`timescale 1ns/1ps
// Active-low user button. Only the ARM input is debounced: stop inputs use
// two-stage synchronizers and a latched disarm in car_decision instead.
module car_button #(
    parameter integer CLK_HZ = 50000000,
    parameter integer DEBOUNCE_MS = 20
) (
    input wire clk, input wire rst_n, input wire button_n,
    output reg press
);
    localparam integer RAW_TICKS = (CLK_HZ / 1000) * DEBOUNCE_MS;
    localparam integer TICKS = RAW_TICKS < 2 ? 2 : RAW_TICKS;
    (* ASYNC_REG = "TRUE" *) reg [1:0] sync_n;
    reg stable_n;
    reg [31:0] count;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_n <= 2'b11; stable_n <= 1'b1; count <= 0; press <= 0;
        end else begin
            sync_n <= {sync_n[0], button_n};
            press <= 0;
            if (sync_n[1] == stable_n) count <= 0;
            else if (count >= TICKS - 1) begin
                count <= 0;
                stable_n <= sync_n[1];
                if (!sync_n[1]) press <= 1;
            end else count <= count + 1'b1;
        end
    end
endmodule
