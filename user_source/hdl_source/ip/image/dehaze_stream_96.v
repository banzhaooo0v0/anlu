`timescale 1ns/1ps
// Four RGB888 pixels per clock; causal 3x3 group-dark window.
// Eleven register stages (input capture through output), no backpressure.
// Missing top/left neighbors are excluded. Mode is latched on valid tuser.
// Bounded five-eighths-strength reciprocal gain, in 1/64 steps.
// Two independent 8x7 products share each PH1P 27x18 DSP multiplier.
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
    reg [5:0] gain8;
    reg [13:0] atmosphere9;
    wire [14:0] product9 [0:11];
    wire [15:0] restored [0:11];
    integer i;

    function [7:0] min2;
        input [7:0] a,b;
        begin min2 = a < b ? a : b; end
    endfunction
    function [7:0] min3;
        input [7:0] a,b,c;
        begin min3 = min2(min2(a,b),c); end
    endfunction

    // k = round(40*(256-t)/t), capped to 48. Effective gain = 1+k/64.
    // Division is evaluated OFFLINE by sim/generate_dehaze_gain_lut.py;
    // the RTL contains only a small constant decoder.
    function [5:0] reciprocal_extra;
        input [9:0] t;
        begin
            case (t)
                10'd103: reciprocal_extra = 6'd48;
                10'd104: reciprocal_extra = 6'd48;
                10'd105: reciprocal_extra = 6'd48;
                10'd106: reciprocal_extra = 6'd48;
                10'd107: reciprocal_extra = 6'd48;
                10'd108: reciprocal_extra = 6'd48;
                10'd109: reciprocal_extra = 6'd48;
                10'd110: reciprocal_extra = 6'd48;
                10'd111: reciprocal_extra = 6'd48;
                10'd112: reciprocal_extra = 6'd48;
                10'd113: reciprocal_extra = 6'd48;
                10'd114: reciprocal_extra = 6'd48;
                10'd115: reciprocal_extra = 6'd48;
                10'd116: reciprocal_extra = 6'd48;
                10'd117: reciprocal_extra = 6'd48;
                10'd118: reciprocal_extra = 6'd47;
                10'd119: reciprocal_extra = 6'd46;
                10'd120: reciprocal_extra = 6'd45;
                10'd121: reciprocal_extra = 6'd45;
                10'd122: reciprocal_extra = 6'd44;
                10'd123: reciprocal_extra = 6'd43;
                10'd124: reciprocal_extra = 6'd43;
                10'd125: reciprocal_extra = 6'd42;
                10'd126: reciprocal_extra = 6'd41;
                10'd127: reciprocal_extra = 6'd41;
                10'd128: reciprocal_extra = 6'd40;
                10'd129: reciprocal_extra = 6'd39;
                10'd130: reciprocal_extra = 6'd39;
                10'd131: reciprocal_extra = 6'd38;
                10'd132: reciprocal_extra = 6'd38;
                10'd133: reciprocal_extra = 6'd37;
                10'd134: reciprocal_extra = 6'd36;
                10'd135: reciprocal_extra = 6'd36;
                10'd136: reciprocal_extra = 6'd35;
                10'd137: reciprocal_extra = 6'd35;
                10'd138: reciprocal_extra = 6'd34;
                10'd139: reciprocal_extra = 6'd34;
                10'd140: reciprocal_extra = 6'd33;
                10'd141: reciprocal_extra = 6'd33;
                10'd142: reciprocal_extra = 6'd32;
                10'd143: reciprocal_extra = 6'd32;
                10'd144: reciprocal_extra = 6'd31;
                10'd145: reciprocal_extra = 6'd31;
                10'd146: reciprocal_extra = 6'd30;
                10'd147: reciprocal_extra = 6'd30;
                10'd148: reciprocal_extra = 6'd29;
                10'd149: reciprocal_extra = 6'd29;
                10'd150: reciprocal_extra = 6'd28;
                10'd151: reciprocal_extra = 6'd28;
                10'd152: reciprocal_extra = 6'd27;
                10'd153: reciprocal_extra = 6'd27;
                10'd154: reciprocal_extra = 6'd26;
                10'd155: reciprocal_extra = 6'd26;
                10'd156: reciprocal_extra = 6'd26;
                10'd157: reciprocal_extra = 6'd25;
                10'd158: reciprocal_extra = 6'd25;
                10'd159: reciprocal_extra = 6'd24;
                10'd160: reciprocal_extra = 6'd24;
                10'd161: reciprocal_extra = 6'd24;
                10'd162: reciprocal_extra = 6'd23;
                10'd163: reciprocal_extra = 6'd23;
                10'd164: reciprocal_extra = 6'd22;
                10'd165: reciprocal_extra = 6'd22;
                10'd166: reciprocal_extra = 6'd22;
                10'd167: reciprocal_extra = 6'd21;
                10'd168: reciprocal_extra = 6'd21;
                10'd169: reciprocal_extra = 6'd21;
                10'd170: reciprocal_extra = 6'd20;
                10'd171: reciprocal_extra = 6'd20;
                10'd172: reciprocal_extra = 6'd20;
                10'd173: reciprocal_extra = 6'd19;
                10'd174: reciprocal_extra = 6'd19;
                10'd175: reciprocal_extra = 6'd19;
                10'd176: reciprocal_extra = 6'd18;
                10'd177: reciprocal_extra = 6'd18;
                10'd178: reciprocal_extra = 6'd18;
                10'd179: reciprocal_extra = 6'd17;
                10'd180: reciprocal_extra = 6'd17;
                10'd181: reciprocal_extra = 6'd17;
                10'd182: reciprocal_extra = 6'd16;
                10'd183: reciprocal_extra = 6'd16;
                10'd184: reciprocal_extra = 6'd16;
                10'd185: reciprocal_extra = 6'd15;
                10'd186: reciprocal_extra = 6'd15;
                10'd187: reciprocal_extra = 6'd15;
                10'd188: reciprocal_extra = 6'd14;
                10'd189: reciprocal_extra = 6'd14;
                10'd190: reciprocal_extra = 6'd14;
                10'd191: reciprocal_extra = 6'd14;
                10'd192: reciprocal_extra = 6'd13;
                10'd193: reciprocal_extra = 6'd13;
                10'd194: reciprocal_extra = 6'd13;
                10'd195: reciprocal_extra = 6'd13;
                10'd196: reciprocal_extra = 6'd12;
                10'd197: reciprocal_extra = 6'd12;
                10'd198: reciprocal_extra = 6'd12;
                10'd199: reciprocal_extra = 6'd11;
                10'd200: reciprocal_extra = 6'd11;
                10'd201: reciprocal_extra = 6'd11;
                10'd202: reciprocal_extra = 6'd11;
                10'd203: reciprocal_extra = 6'd10;
                10'd204: reciprocal_extra = 6'd10;
                10'd205: reciprocal_extra = 6'd10;
                10'd206: reciprocal_extra = 6'd10;
                10'd207: reciprocal_extra = 6'd9;
                10'd208: reciprocal_extra = 6'd9;
                10'd209: reciprocal_extra = 6'd9;
                10'd210: reciprocal_extra = 6'd9;
                10'd211: reciprocal_extra = 6'd9;
                10'd212: reciprocal_extra = 6'd8;
                10'd213: reciprocal_extra = 6'd8;
                10'd214: reciprocal_extra = 6'd8;
                10'd215: reciprocal_extra = 6'd8;
                10'd216: reciprocal_extra = 6'd7;
                10'd217: reciprocal_extra = 6'd7;
                10'd218: reciprocal_extra = 6'd7;
                10'd219: reciprocal_extra = 6'd7;
                10'd220: reciprocal_extra = 6'd7;
                10'd221: reciprocal_extra = 6'd6;
                10'd222: reciprocal_extra = 6'd6;
                10'd223: reciprocal_extra = 6'd6;
                10'd224: reciprocal_extra = 6'd6;
                10'd225: reciprocal_extra = 6'd6;
                10'd226: reciprocal_extra = 6'd5;
                10'd227: reciprocal_extra = 6'd5;
                10'd228: reciprocal_extra = 6'd5;
                10'd229: reciprocal_extra = 6'd5;
                10'd230: reciprocal_extra = 6'd5;
                10'd231: reciprocal_extra = 6'd4;
                10'd232: reciprocal_extra = 6'd4;
                10'd233: reciprocal_extra = 6'd4;
                10'd234: reciprocal_extra = 6'd4;
                10'd235: reciprocal_extra = 6'd4;
                10'd236: reciprocal_extra = 6'd3;
                10'd237: reciprocal_extra = 6'd3;
                10'd238: reciprocal_extra = 6'd3;
                10'd239: reciprocal_extra = 6'd3;
                10'd240: reciprocal_extra = 6'd3;
                10'd241: reciprocal_extra = 6'd2;
                10'd242: reciprocal_extra = 6'd2;
                10'd243: reciprocal_extra = 6'd2;
                10'd244: reciprocal_extra = 6'd2;
                10'd245: reciprocal_extra = 6'd2;
                10'd246: reciprocal_extra = 6'd2;
                10'd247: reciprocal_extra = 6'd1;
                10'd248: reciprocal_extra = 6'd1;
                10'd249: reciprocal_extra = 6'd1;
                10'd250: reciprocal_extra = 6'd1;
                10'd251: reciprocal_extra = 6'd1;
                10'd252: reciprocal_extra = 6'd1;
                10'd253: reciprocal_extra = 6'd0;
                10'd254: reciprocal_extra = 6'd0;
                10'd255: reciprocal_extra = 6'd0;
                10'd256: reciprocal_extra = 6'd0;
                default: reciprocal_extra = 6'd48;
            endcase
        end
    endfunction

    // I +/- round(abs(I-A)*k/64) is exactly
    // floor((I*(64+k)-A*k+(I>=A ? 32 : 31))/64).
    // Share A*k across all channels; avoid 12 absolute-value datapaths.
    // Constant A is implemented explicitly by shifts/adds, not another DSP.
    function [13:0] atmospheric_product;
        input [5:0] k;
        integer bit_index;
        reg [13:0] accum;
        begin
            accum = 0;
            for (bit_index=0; bit_index<8; bit_index=bit_index+1)
                if ((ATMOSPHERIC_LIGHT >> bit_index) & 1)
                    accum = accum + ({8'd0,k} << bit_index);
            atmospheric_product = accum;
        end
    endfunction

    // Pack two pixels 15 bits apart, sharing their common 7-bit gain.
    // 255*127+32 < 2^15, including rounding: lanes cannot carry into each other.
    // 23x7 fits one PH1P 27x18 DSP. S9/S10 and all control latency are unchanged.
    genvar c;
    generate for (c=0; c<6; c=c+1) begin: g_packed_mult
        wire [7:0] low_pixel = pixels[8][(2*c)*8+:8];
        wire [7:0] high_pixel = pixels[8][(2*c+1)*8+:8];
        wire [22:0] packed_pixels = {high_pixel,7'd0,low_pixel};
        wire [29:0] packed_product = packed_pixels * {1'b1,gain8};
        wire [14:0] low_round = low_pixel >= ATMOSPHERIC_LIGHT ? 15'd32 : 15'd31;
        wire [14:0] high_round = high_pixel >= ATMOSPHERIC_LIGHT ? 15'd32 : 15'd31;
        reg [29:0] rounded9;
        always @(posedge I_clk or negedge I_rst_n) begin
            if (!I_rst_n) rounded9 <= 0;
            else rounded9 <= packed_product + {high_round,low_round};
        end
        assign product9[2*c] = rounded9[14:0];
        assign product9[2*c+1] = rounded9[29:15];
    end endgenerate
    generate for (c=0; c<12; c=c+1) begin: g_restore
        // A signed result in Q6; sign and bit14 implement the two clip bounds.
        assign restored[c] = {1'b0,product9[c]} - {2'd0,atmosphere9};
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
            atmosphere9 <= 0;
            O_tvalid <= 0; O_tuser <= 0; O_tlast <= 0; O_tdata <= 0;
            for (i=0; i<10; i=i+1) pixels[i] <= 0;
            for (i=0; i<4; i=i+1) pixel_min1[i] <= 0;
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
            // S6/S7 transmission; S8 bounded fine-step reciprocal decoder.
            product6 <= window5 * OMEGA_Q8;
            transmission7 <= estimate6 < MIN_TRANSMISSION ? MIN_TRANSMISSION : estimate6;
            gain8 <= reciprocal_extra(transmission7);
            atmosphere9 <= atmospheric_product(gain8);
            for (i=0; i<12; i=i+1) begin
                // S10 saturation or a bypass with exactly the same latency.
                O_tdata[i*8+:8] <= !enable_pipe[9] ? pixels[9][i*8+:8] :
                    (restored[i][15] ? 8'd0 : (restored[i][14] ? 8'hff : restored[i][13:6]));
            end
            O_tvalid <= valid_pipe[9];
            O_tuser <= user_pipe[9];
            O_tlast <= last_pipe[9];
        end
    end
endmodule
