`timescale 1ns/1ps
// Bundled-data mailbox. The source holds ASCII until the destination ACK
// crosses back; req/ack each pass two synchronizers. A busy mailbox retains
// the latest source result, without tearing its byte or duplicating an event.
module car_result_cdc (
    input wire src_clk, input wire src_rst_n,
    input wire [7:0] src_ascii, input wire src_toggle,
    input wire dst_clk, input wire dst_rst_n,
    output reg [7:0] dst_ascii, output reg dst_valid
);
    wire reset_n = src_rst_n && dst_rst_n;
    (* ASYNC_REG = "TRUE" *) reg [1:0] src_reset, dst_reset;
    (* ASYNC_REG = "TRUE" *) reg [1:0] ack_sync, req_sync;
    reg req, ack, seen;
    reg [7:0] mailbox, pending_ascii;
    reg pending;
    reg capture;
    always @(posedge src_clk or negedge reset_n)
        if (!reset_n) src_reset <= 0; else src_reset <= {src_reset[0],1'b1};
    always @(posedge dst_clk or negedge reset_n)
        if (!reset_n) dst_reset <= 0; else dst_reset <= {dst_reset[0],1'b1};
    always @(posedge src_clk or negedge reset_n) begin
        if (!reset_n) begin
            ack_sync <= 0; req <= 0; seen <= 0; mailbox <= "?";
            pending_ascii <= "?"; pending <= 0;
        end else if (!src_reset[1]) begin
            // Align to the current toggle during reset release; only a new
            // post-reset source event may establish destination freshness.
            ack_sync <= 0; req <= 0; seen <= src_toggle; pending <= 0;
        end else begin
            ack_sync <= {ack_sync[0],ack};
            if (src_toggle != seen) begin
                seen <= src_toggle;
                if (req == ack_sync[1]) begin
                    mailbox <= src_ascii; req <= ~req; pending <= 0;
                end else begin
                    pending_ascii <= src_ascii; pending <= 1;
                end
            end else if (pending && req == ack_sync[1]) begin
                mailbox <= pending_ascii; req <= ~req; pending <= 0;
            end
        end
    end
    always @(posedge dst_clk or negedge reset_n) begin
        if (!reset_n) begin
            req_sync <= 0; ack <= 0; capture <= 0;
            dst_ascii <= "?"; dst_valid <= 0;
        end else if (!dst_reset[1]) begin
            req_sync <= 0; ack <= 0; capture <= 0; dst_valid <= 0;
        end else begin
            req_sync <= {req_sync[0],req};
            dst_valid <= 0;
            if (capture) begin
                dst_ascii <= mailbox; dst_valid <= 1;
                ack <= req_sync[1]; capture <= 0;
            end else if (req_sync[1] != ack) capture <= 1;
        end
    end
endmodule
