`timescale 1ns / 1ps
// SC500CS analogue gain codes from datasheet table 2-4.
// Index 0..127 covers 1.0x..15.75x in four 32-step ranges.
module SC500GainTbl (
    input  wire       I_clk,
    input  wire       I_rstn,
    input  wire [6:0] I,
    output reg [15:0] O
);
    wire [7:0] coarse = I[6:5] == 2'd0 ? 8'h03 :
                        I[6:5] == 2'd1 ? 8'h07 :
                        I[6:5] == 2'd2 ? 8'h0f : 8'h1f;
    always @(posedge I_clk or negedge I_rstn) begin
        if (!I_rstn)
            O <= 16'h0320;
        else
            O <= {coarse, 3'b001, I[4:0]};
    end
endmodule
