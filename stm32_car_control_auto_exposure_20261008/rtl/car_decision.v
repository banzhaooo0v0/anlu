`timescale 1ns/1ps
// Conservative four-wheel differential demo policy. STM32 owns wheel PI loops.
// The current teammate detector exports L, R and ? only; ? is unknown/no target.
// Turns are timed, not angle-controlled. Obstacles come from an external input.
module car_decision #(
    parameter integer CLK_HZ = 50000000,
    parameter integer CONFIRM_FRAMES = 3,
    parameter integer CLEAR_FRAMES = 3,
    parameter integer RESULT_TIMEOUT_MS = 500,
    parameter integer TURN_MS = 800,
    parameter integer FORWARD_MM_S = 100,
    parameter integer SLOW_MM_S = 50,
    parameter integer TURN_MM_S = 50,
    parameter integer TURN_MRAD_S = 250
) (
    input wire clk, input wire rst_n, input wire arm_pulse,
    input wire estop, input wire obstacle, input wire slow,
    input wire result_valid, input wire [7:0] result_ascii,
    input wire link_ok, input wire [7:0] flag_stop,
    output reg armed, output reg [2:0] state,
    output reg signed [15:0] cmd_vx, cmd_vy, cmd_wz,
    output wire force_zero, output wire result_stale
);
    localparam [2:0] STOP=0, FORWARD=1, LEFT=2, RIGHT=3,
                     OBSTACLE=4, SLOW=5, FAULT=6;
    localparam integer AGE_TICKS = (CLK_HZ / 1000) * RESULT_TIMEOUT_MS;
    localparam integer TURN_TICKS = (CLK_HZ / 1000) * TURN_MS;
    reg have_result;
    reg [31:0] result_age, turn_age;
    reg [7:0] vote_ascii;
    reg [15:0] vote_count, clear_count;
    reg turn_locked;
    assign result_stale = !have_result || result_age >= AGE_TICKS;
    wire unsafe = estop || obstacle || !link_ok || flag_stop != 0 || result_stale;
    assign force_zero = !armed || unsafe;
    always @* begin
        cmd_vx = 0; cmd_vy = 0; cmd_wz = 0;
        if (!force_zero) begin
            case (state)
                FORWARD: cmd_vx = FORWARD_MM_S;
                SLOW: cmd_vx = SLOW_MM_S;
                LEFT: begin cmd_vx = TURN_MM_S; cmd_wz = TURN_MRAD_S; end
                RIGHT: begin cmd_vx = TURN_MM_S; cmd_wz = -TURN_MRAD_S; end
                default: begin cmd_vx = 0; cmd_wz = 0; end
            endcase
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            have_result <= 0; result_age <= AGE_TICKS;
        end else if (result_valid) begin
            have_result <= 1; result_age <= 0;
        end else if (result_age < AGE_TICKS) result_age <= result_age + 1'b1;
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            armed <= 0; state <= STOP; turn_age <= 0;
            vote_ascii <= "?"; vote_count <= 0; clear_count <= 0; turn_locked <= 0;
        end else if (unsafe) begin
            armed <= 0;
            if (obstacle) state <= OBSTACLE;
            else if (estop) state <= STOP;
            else state <= FAULT;
            vote_count <= 0; vote_ascii <= "?";
            turn_age <= 0; turn_locked <= 0; clear_count <= 0;
        end else if (!armed) begin
            state <= STOP; vote_count <= 0; vote_ascii <= "?";
            turn_age <= 0; turn_locked <= 0; clear_count <= 0;
            if (arm_pulse) begin armed <= 1; state <= slow ? SLOW : FORWARD; end
        end else if (state == LEFT || state == RIGHT) begin
            // Subsequent recognition results never restart an active turn.
            if (turn_age >= TURN_TICKS - 1) begin
                state <= slow ? SLOW : FORWARD; turn_age <= 0;
            end else turn_age <= turn_age + 1'b1;
            vote_count <= 0; clear_count <= 0;
        end else begin
            state <= slow ? SLOW : FORWARD;
            if (result_valid) begin
                if (turn_locked) begin
                    vote_count <= 0;
                    if (result_ascii == "?") begin
                        if (clear_count >= CLEAR_FRAMES - 1) begin
                            turn_locked <= 0; clear_count <= 0;
                        end else clear_count <= clear_count + 1'b1;
                    end else clear_count <= 0;
                end else if (result_ascii == "L" || result_ascii == "R") begin
                    if ((vote_ascii == result_ascii && vote_count >= CONFIRM_FRAMES - 1)
                        || CONFIRM_FRAMES <= 1) begin
                        state <= result_ascii == "L" ? LEFT : RIGHT;
                        turn_age <= 0; turn_locked <= 1; vote_count <= 0;
                    end else begin
                        vote_ascii <= result_ascii;
                        if (vote_ascii == result_ascii) vote_count <= vote_count + 1'b1;
                        else vote_count <= 1;
                    end
                end else begin vote_count <= 0; vote_ascii <= "?"; end
            end
        end
    end
endmodule
