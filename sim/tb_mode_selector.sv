`timescale 1ns / 1ps

module tb_mode_selector;

    reg clk;
    reg rst_n;
    reg [1:0] button;
    wire [1:0] mode;
    integer error_count;

    mode_selector #(
        .DEBOUNCE_CYCLES(3)
    ) dut (
        .I_clk   (clk),
        .I_rst_n (rst_n),
        .I_button(button),
        .I_cycle_button_n(1'b1),
        .O_mode  (mode)
    );

    always #5 clk = ~clk;

    task check_mode;
        input [1:0] requested_button;
        input [1:0] expected_mode;
        integer cycle;
        begin
            button = requested_button;
            for (cycle = 0; cycle < 10; cycle = cycle + 1)
                @(posedge clk);
            if (mode !== expected_mode) begin
                $display("[FAIL] button=%b got mode=%b expected=%b", requested_button, mode, expected_mode);
                error_count = error_count + 1;
            end
            else begin
                $display("[PASS] button=%b mode=%b", requested_button, mode);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        rst_n = 1'b0;
        button = 2'b11;
        error_count = 0;

        repeat (3) @(posedge clk);
        rst_n = 1'b1;

        check_mode(2'b11, 2'b11);
        check_mode(2'b10, 2'b10);
        check_mode(2'b01, 2'b01);
        check_mode(2'b00, 2'b00);
        check_mode(2'b11, 2'b11);

        if (error_count == 0)
            $display("[RESULT] ALL MODE SELECTOR TESTS PASSED");
        else
            $display("[RESULT] MODE SELECTOR FAILURES=%0d", error_count);
        $finish;
    end

endmodule
