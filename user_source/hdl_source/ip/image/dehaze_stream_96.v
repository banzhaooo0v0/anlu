`timescale 1ns/1ps
// Four RGB888 pixels per clock; causal 3x3 group-dark window.
// Eleven register stages (input capture through output), no backpressure.
// Missing top/left neighbors are excluded. Mode is latched on valid tuser.
module dehaze_stream_96 #(
    parameter integer IMG_WIDTH = 1280,
    parameter integer IMG_HEIGHT = 720,
    parameter integer ATMOSPHERIC_LIGHT = 240,
    parameter integer OMEGA_Q8 = 218,
    parameter integer MIN_TRANSMISSION = 64
) (
    input wire I_clk, I_rst_n, I_tuser, I_tlast, I_tvalid,
    input wire [95:0] I_tdata,
    input wire I_enable,
    output reg O_tuser, O_tlast, O_tvalid,
    output reg [95:0] O_tdata
);
    localparam integer GROUP_WIDTH = IMG_WIDTH/4;
    localparam integer XW = GROUP_WIDTH <= 1 ? 1 : $clog2(GROUP_WIDTH);
    localparam integer YW = IMG_HEIGHT <= 1 ? 1 : $clog2(IMG_HEIGHT);
    reg [7:0] dark_line_a [0:GROUP_WIDTH-1];
    reg [7:0] dark_line_b [0:GROUP_WIDTH-1];
    reg [95:0] pixels [0:9];
    reg [9:0] valid_pipe, user_pipe, last_pipe, enable_pipe;
    reg frame_enable;
    reg [XW-1:0] x_count, x1, x2, x3, x4;
    reg [YW-1:0] y_count, y1, y2;
    wire [XW-1:0] active_x = user_pipe[0] ? {XW{1'b0}} : x_count;
    wire [YW-1:0] active_y = user_pipe[0] ? {YW{1'b0}} : y_count;
    reg [7:0] pixel_min1 [0:3];
    reg [7:0] dark2, row_top3, row_mid3, row_cur3, vertical4;
    reg [7:0] left1, left2, window5;
    reg [15:0] product6;
    wire [9:0] estimate6 = 10'd256 - ((product6 + 16'd128) >> 8);
    reg [9:0] transmission7;
    reg [2:0] gain8;
    reg [8:0] magnitude8 [0:11];
    reg [11:0] positive8, positive9;
    reg [8:0] correction9 [0:11];
    wire [9:0] restored [0:11];
    integer i;

    function [7:0] min2;
        input [7:0] a,b;
        begin min2 = a < b ? a : b; end
    endfunction
    function [7:0] min3;
        input [7:0] a,b,c;
        begin min3 = min2(min2(a,b),c); end
    endfunction

    // One final add/subtract per channel, after the gain has been applied.
    genvar c;
    generate for (c=0; c<12; c=c+1) begin: g_restore
        assign restored[c] = positive9[c] ? ATMOSPHERIC_LIGHT + correction9[c] :
            (correction9[c] > ATMOSPHERIC_LIGHT ? 10'd0 : ATMOSPHERIC_LIGHT - correction9[c]);
    end endgenerate

    // Memories are intentionally not reset, allowing RAM inference. Each
    // location is written before a later row may use it; y2 masks old rows.
    always @(posedge I_clk) begin
        if (valid_pipe[2]) begin
            dark_line_b[x2] <= dark_line_a[x2];
            dark_line_a[x2] <= dark2;
        end
    end

    always @(posedge I_clk or negedge I_rst_n) begin
        if (!I_rst_n) begin
            valid_pipe <= 0; user_pipe <= 0; last_pipe <= 0; enable_pipe <= 0;
            frame_enable <= 0;
            x_count <= 0; y_count <= 0;
            x1 <= 0; x2 <= 0; x3 <= 0; x4 <= 0; y1 <= 0; y2 <= 0;
            dark2 <= 0; row_top3 <= 0; row_mid3 <= 0; row_cur3 <= 0;
            vertical4 <= 0; left1 <= 0; left2 <= 0; window5 <= 0;
            product6 <= 0; transmission7 <= 0; gain8 <= 0;
            positive8 <= 0; positive9 <= 0;
            O_tvalid <= 0; O_tuser <= 0; O_tlast <= 0; O_tdata <= 0;
            for (i=0; i<10; i=i+1) pixels[i] <= 0;
            for (i=0; i<4; i=i+1) pixel_min1[i] <= 0;
            for (i=0; i<12; i=i+1) begin magnitude8[i] <= 0; correction9[i] <= 0; end
        end else begin
            // S0 isolates AWB's combinational output from the dark-channel tree.
            pixels[0] <= I_tdata;
            valid_pipe <= {valid_pipe[8:0], I_tvalid};
            user_pipe <= {user_pipe[8:0], I_tvalid && I_tuser};
            last_pipe <= {last_pipe[8:0], I_tvalid && I_tlast};
            enable_pipe[0] <= I_enable;
            enable_pipe[1] <= user_pipe[0] ? enable_pipe[0] : frame_enable;
            for (i=1; i<10; i=i+1) pixels[i] <= pixels[i-1];
            for (i=2; i<10; i=i+1) enable_pipe[i] <= enable_pipe[i-1];

            // S1 per-pixel minimum and coordinates; counters advance on valid only.
            for (i=0; i<4; i=i+1)
                pixel_min1[i] <= min3(pixels[0][i*24+:8],pixels[0][i*24+8+:8],pixels[0][i*24+16+:8]);
            if (valid_pipe[0]) begin
                x1 <= active_x; y1 <= active_y;
                if (user_pipe[0]) frame_enable <= enable_pipe[0];
                if (last_pipe[0]) begin
                    x_count <= 0;
                    y_count <= active_y == IMG_HEIGHT-1 ? {YW{1'b0}} : active_y + 1'b1;
                end else begin
                    x_count <= active_x + 1'b1;
                    y_count <= active_y;
                end
            end
            // S2 group minimum. S3 reads the two previous rows.
            dark2 <= min2(min2(pixel_min1[0],pixel_min1[1]),min2(pixel_min1[2],pixel_min1[3]));
            x2 <= x1; y2 <= y1;
            x3 <= x2;
            row_cur3 <= dark2;
            row_mid3 <= y2 == 0 ? 8'hff : dark_line_a[x2];
            row_top3 <= y2 < 2 ? 8'hff : dark_line_b[x2];
            // S4/S5 separable 3x3 minimum, equivalent to nine comparisons.
            x4 <= x3;
            vertical4 <= min3(row_top3,row_mid3,row_cur3);
            if (valid_pipe[4]) begin
                window5 <= min3(vertical4, x4 == 0 ? 8'hff : left1, x4 < 2 ? 8'hff : left2);
                left1 <= vertical4;
                left2 <= left1;
            end
            // S6/S7 fixed-point transmission. S8 chooses the reciprocal segment.
            product6 <= window5 * OMEGA_Q8;
            transmission7 <= estimate6 < MIN_TRANSMISSION ? MIN_TRANSMISSION : estimate6;
            if (transmission7 >= 240) gain8 <= 0;
            else if (transmission7 >= 224) gain8 <= 1;
            else if (transmission7 >= 192) gain8 <= 2;
            else if (transmission7 >= 160) gain8 <= 3;
            else if (transmission7 >= 128) gain8 <= 4;
            else gain8 <= 5;
            for (i=0; i<12; i=i+1) begin
                positive8[i] <= pixels[7][i*8+:8] >= ATMOSPHERIC_LIGHT;
                magnitude8[i] <= pixels[7][i*8+:8] >= ATMOSPHERIC_LIGHT ?
                    pixels[7][i*8+:8] - ATMOSPHERIC_LIGHT : ATMOSPHERIC_LIGHT - pixels[7][i*8+:8];
                // S9 shift/add gain on unsigned magnitude, preserving rounding.
                case (gain8)
                    0: correction9[i] <= magnitude8[i];
                    1: correction9[i] <= magnitude8[i] + (magnitude8[i] >> 4);
                    2: correction9[i] <= magnitude8[i] + (magnitude8[i] >> 2);
                    3: correction9[i] <= magnitude8[i] + (magnitude8[i] >> 1);
                    4: correction9[i] <= magnitude8[i] + (magnitude8[i] >> 1) + (magnitude8[i] >> 2);
                    default: correction9[i] <= magnitude8[i] << 1;
                endcase
                // S10 saturation or a bypass with exactly the same latency.
                O_tdata[i*8+:8] <= !enable_pipe[9] ? pixels[9][i*8+:8] :
                    (restored[i] > 255 ? 8'hff : restored[i][7:0]);
            end
            positive9 <= positive8;
            O_tvalid <= valid_pipe[9];
            O_tuser <= user_pipe[9];
            O_tlast <= last_pipe[9];
        end
    end
endmodule
