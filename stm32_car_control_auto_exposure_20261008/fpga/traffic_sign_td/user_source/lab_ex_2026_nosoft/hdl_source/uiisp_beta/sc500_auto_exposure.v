`timescale 1ns / 1ps
// SC500CS frame-based auto exposure and analogue gain control.
// RAW10 input contains four Bayer pixels per beat; bits [19:10] select
// one green pixel, so the meter is independent of the AWB/HDMI overlay.
module sc500_auto_exposure #(
    parameter [15:0] EXP_MIN = 16'd6,
    // SC500CS manual exposure maximum: 2*VTS-10, VTS=1000 in this project.
    parameter [15:0] EXP_MAX = 16'd1990,
    parameter [9:0]  LUMA_LOW = 10'd350,
    parameter [9:0]  LUMA_HIGH = 10'd470
) (
    input  wire        I_raw_clk,
    input  wire        I_raw_rst_n,
    input  wire        I_raw_frame_start,
    input  wire        I_raw_frame_end,
    input  wire        I_raw_valid,
    input  wire [39:0] I_raw_data,
    input  wire        I_cfg_clk,
    input  wire        I_cfg_rst,
    input  wire        I_cam_cfg_done,
    input  wire        I_ae_cfg_done,
    output reg         O_ae_req,
    output reg  [15:0] O_ae,
    output wire [15:0] O_ag
);
    // One of every 32 four-pixel beats is enough for a frame-wide meter.
    reg        frame_active;
    reg [4:0]  sample_div;
    reg [31:0] frame_sum;
    reg [15:0] frame_count;
    reg [15:0] frame_clipped;
    reg [31:0] transfer_sum;
    reg [15:0] transfer_count;
    reg [15:0] transfer_clipped;
    reg        transfer_toggle;
    reg        ack_sync_1, ack_sync_2;
    reg        ack_toggle;

    always @(posedge I_raw_clk or negedge I_raw_rst_n) begin
        if (!I_raw_rst_n) begin
            frame_active     <= 1'b0;
            sample_div       <= 5'd0;
            frame_sum        <= 32'd0;
            frame_count      <= 16'd0;
            frame_clipped    <= 16'd0;
            transfer_sum     <= 32'd0;
            transfer_count   <= 16'd0;
            transfer_clipped <= 16'd0;
            transfer_toggle  <= 1'b0;
            ack_sync_1      <= 1'b0;
            ack_sync_2      <= 1'b0;
        end else begin
            ack_sync_1 <= ack_toggle;
            ack_sync_2 <= ack_sync_1;
            if (I_raw_frame_start) begin
                frame_active  <= 1'b1;
                sample_div    <= 5'd0;
                frame_sum     <= 32'd0;
                frame_count   <= 16'd0;
                frame_clipped <= 16'd0;
            end else if (I_raw_frame_end) begin
                frame_active <= 1'b0;
                // Hold the payload until the receiving clock acknowledges it.
                if (frame_count >= 16'd256 &&
                    transfer_toggle == ack_sync_2) begin
                    transfer_sum     <= frame_sum;
                    transfer_count   <= frame_count;
                    transfer_clipped <= frame_clipped;
                    transfer_toggle  <= ~transfer_toggle;
                end
            end else if (frame_active && I_raw_valid) begin
                sample_div <= sample_div + 1'b1;
                if (sample_div == 5'd0) begin
                    frame_sum   <= frame_sum + {22'd0, I_raw_data[19:10]};
                    frame_count <= frame_count + 1'b1;
                    if (I_raw_data[19:10] >= 10'd960)
                        frame_clipped <= frame_clipped + 1'b1;
                end
            end
        end
    end

    reg req_sync_1, req_sync_2;
    reg [1:0] settle_frames;
    reg [6:0] gain_index;
    // This project's initial sensor table programs exposure=1990 and 4x
    // analogue gain. Index 64 in SC500GainTbl corresponds to 0x0f20 (4x).
    assign O_ag = {9'd0, gain_index} + 16'd16;

    wire [31:0] low_limit = transfer_count * LUMA_LOW;
    wire [31:0] high_limit = transfer_count * LUMA_HIGH;
    wire [31:0] very_low_limit = transfer_count * (LUMA_LOW >> 1);
    wire overbright = (transfer_sum > high_limit) ||
                      (transfer_clipped > (transfer_count >> 3));
    wire underbright = transfer_sum < low_limit;
    wire very_dark = transfer_sum < very_low_limit;

    always @(posedge I_cfg_clk or posedge I_cfg_rst) begin
        if (I_cfg_rst) begin
            req_sync_1   <= 1'b0;
            req_sync_2   <= 1'b0;
            ack_toggle   <= 1'b0;
            settle_frames<= 2'd0;
            O_ae_req     <= 1'b0;
            O_ae         <= 16'd1990;
            gain_index   <= 7'd64;
        end else begin
            req_sync_1 <= transfer_toggle;
            req_sync_2 <= req_sync_1;
            O_ae_req <= 1'b0;
            if (req_sync_2 != ack_toggle) begin
                ack_toggle <= req_sync_2;
                // A write in frame N takes effect in frame N+2. Skip the
                // intervening frames before using their brightness feedback.
                if (settle_frames != 2'd0)
                    settle_frames <= settle_frames - 1'b1;
                else if (I_cam_cfg_done && I_ae_cfg_done) begin
                    if (overbright) begin
                        if (gain_index != 7'd0) begin
                            gain_index <= gain_index > 7'd4 ?
                                          gain_index - 7'd4 : 7'd0;
                            O_ae_req <= 1'b1;
                            settle_frames <= 2'd2;
                        end else if (O_ae > EXP_MIN) begin
                            O_ae <= O_ae > (EXP_MIN + 16'd64) ?
                                    O_ae - 16'd64 : EXP_MIN;
                            O_ae_req <= 1'b1;
                            settle_frames <= 2'd2;
                        end
                    end else if (underbright) begin
                        if (O_ae < EXP_MAX) begin
                            O_ae <= O_ae < (EXP_MAX - 16'd64) ?
                                    O_ae + 16'd64 : EXP_MAX;
                            O_ae_req <= 1'b1;
                            settle_frames <= 2'd2;
                        end else if (gain_index < 7'd127) begin
                            gain_index <= very_dark && gain_index <= 7'd119 ?
                                          gain_index + 7'd8 :
                                          (gain_index <= 7'd123 ?
                                           gain_index + 7'd4 : 7'd127);
                            O_ae_req <= 1'b1;
                            settle_frames <= 2'd2;
                        end
                    end
                end
            end
        end
    end
endmodule
