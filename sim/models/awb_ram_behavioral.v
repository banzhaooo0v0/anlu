`timescale 1ns/1ps
// Portable memory-contract model for ADDRESS/DEPTH equivalence testing only.
// This is not Anlogic's encrypted primitive and does not validate its timing.
// Do not include this file in the TD synthesis project.
module ram_f84573da5ab5 #(
    parameter DATA_WIDTH_A=20, ADDR_WIDTH_A=10, DATA_DEPTH_A=1024,
    parameter DATA_WIDTH_B=DATA_WIDTH_A, ADDR_WIDTH_B=ADDR_WIDTH_A,
    parameter DATA_DEPTH_B=DATA_DEPTH_A,
    parameter REGMODE_A="NOREG", REGMODE_B="OUTREG",
    parameter WRITEMODE_A="NORMAL", WRITEMODE_B="NORMAL",
    parameter RESETMODE_A="ASYNC", RESETMODE_B="ASYNC",
    parameter INIT_FILE="NONE", FILL_ALL="NONE"
) (
    output reg [DATA_WIDTH_A-1:0] doa,
    input [DATA_WIDTH_A-1:0] dia,
    input [ADDR_WIDTH_A-1:0] addra,
    input clka,wea,clkb,web,
    output reg [DATA_WIDTH_B-1:0] dob,
    input [DATA_WIDTH_B-1:0] dib,
    input [ADDR_WIDTH_B-1:0] addrb
);
    reg [DATA_WIDTH_A-1:0] mem[0:DATA_DEPTH_A-1];
    always @(posedge clka) begin
        if (wea) begin
            if (addra >= DATA_DEPTH_A) $fatal(1,"AWB write out of bounds");
            mem[addra] <= dia;
        end
        doa <= mem[addra];
    end
    always @(posedge clkb) begin
        if (addrb >= DATA_DEPTH_B) $fatal(1,"AWB read out of bounds");
        if (web) mem[addrb] <= dib;
        dob <= mem[addrb];
    end
endmodule
