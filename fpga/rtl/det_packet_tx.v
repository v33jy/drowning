`timescale 1ns / 1ps

module det_packet_tx #(
    parameter integer CLOCK_HZ  = 100_000_000,
    parameter integer BAUD_RATE = 115_200
)(
    input  wire        clk,
    input  wire        reset,
    input  wire        start,
    input  wire        detected,
    input  wire [9:0]  peak_bin,
    input  wire [41:0] peak_power,

    output wire        tx,
    output reg         busy,
    output reg         done
);

    localparam [2:0] STATE_IDLE        = 3'd0;
    localparam [2:0] STATE_BIN_CONVERT = 3'd1;
    localparam [2:0] STATE_MAG_CONVERT = 3'd2;
    localparam [2:0] STATE_SEND        = 3'd3;

    reg [2:0] state;

    reg       detected_latched;
    reg [9:0] bin_temp;
    reg [31:0] magnitude_temp;

    reg [15:0] bin_bcd;
    reg [39:0] magnitude_bcd;
    reg [3:0]  convert_count;

    reg [4:0] char_index;
    reg [7:0] uart_data;
    reg       uart_start;
    reg       byte_in_flight;
    wire      uart_busy;
    wire      uart_done;

    // 전력값은 UART 표시용으로 2^10만큼 축소합니다.
    // 원래 42비트 peak_power는 spectrum_analyzer 내부에 그대로 유지됩니다.
    wire [31:0] magnitude_scaled;
    wire [3:0]  bin_remainder;
    wire [3:0]  magnitude_remainder;

    assign magnitude_scaled    = peak_power[41:10];
    assign bin_remainder       = bin_temp % 10;
    assign magnitude_remainder = magnitude_temp % 10;

    uart_tx #(
        .CLOCK_HZ  (CLOCK_HZ),
        .BAUD_RATE (BAUD_RATE)
    ) u_uart_tx (
        .clk   (clk),
        .reset (reset),
        .start (uart_start),
        .data  (uart_data),
        .tx    (tx),
        .busy  (uart_busy),
        .done  (uart_done)
    );

    function [7:0] packet_character;
        input [4:0] index;
        begin
            case (index)
                5'd0:  packet_character = "D";
                5'd1:  packet_character = "E";
                5'd2:  packet_character = "T";
                5'd3:  packet_character = ",";
                5'd4:  packet_character = detected_latched ? "1" : "0";
                5'd5:  packet_character = ",";
                5'd6:  packet_character = "0" + bin_bcd[15:12];
                5'd7:  packet_character = "0" + bin_bcd[11:8];
                5'd8:  packet_character = "0" + bin_bcd[7:4];
                5'd9:  packet_character = "0" + bin_bcd[3:0];
                5'd10: packet_character = ",";
                5'd11: packet_character = "0" + magnitude_bcd[39:36];
                5'd12: packet_character = "0" + magnitude_bcd[35:32];
                5'd13: packet_character = "0" + magnitude_bcd[31:28];
                5'd14: packet_character = "0" + magnitude_bcd[27:24];
                5'd15: packet_character = "0" + magnitude_bcd[23:20];
                5'd16: packet_character = "0" + magnitude_bcd[19:16];
                5'd17: packet_character = "0" + magnitude_bcd[15:12];
                5'd18: packet_character = "0" + magnitude_bcd[11:8];
                5'd19: packet_character = "0" + magnitude_bcd[7:4];
                5'd20: packet_character = "0" + magnitude_bcd[3:0];
                5'd21: packet_character = 8'h0D;
                5'd22: packet_character = 8'h0A;
                default: packet_character = 8'h20;
            endcase
        end
    endfunction

    always @(posedge clk) begin
        uart_start <= 1'b0;
        done       <= 1'b0;

        if (reset) begin
            state              <= STATE_IDLE;
            detected_latched   <= 1'b0;
            bin_temp           <= 10'd0;
            magnitude_temp     <= 32'd0;
            bin_bcd            <= 16'd0;
            magnitude_bcd      <= 40'd0;
            convert_count      <= 4'd0;
            char_index         <= 5'd0;
            uart_data          <= 8'd0;
            uart_start         <= 1'b0;
            byte_in_flight     <= 1'b0;
            busy               <= 1'b0;
            done               <= 1'b0;
        end
        else begin
            case (state)
                STATE_IDLE: begin
                    busy <= 1'b0;

                    if (start) begin
                        detected_latched <= detected;
                        bin_temp         <= peak_bin;
                        magnitude_temp   <= magnitude_scaled;
                        bin_bcd          <= 16'd0;
                        magnitude_bcd    <= 40'd0;
                        convert_count    <= 4'd0;
                        busy             <= 1'b1;
                        state            <= STATE_BIN_CONVERT;
                    end
                end

                STATE_BIN_CONVERT: begin
                    // 4자리 십진수: 0000~1023
                    bin_bcd <= {
                        bin_remainder,
                        bin_bcd[15:4]
                    };
                    bin_temp <= bin_temp / 10;

                    if (convert_count == 4'd3) begin
                        convert_count <= 4'd0;
                        state         <= STATE_MAG_CONVERT;
                    end
                    else begin
                        convert_count <= convert_count + 1'b1;
                    end
                end

                STATE_MAG_CONVERT: begin
                    // 10자리 십진수
                    magnitude_bcd <= {
                        magnitude_remainder,
                        magnitude_bcd[39:4]
                    };
                    magnitude_temp <= magnitude_temp / 10;

                    if (convert_count == 4'd9) begin
                        convert_count <= 4'd0;
                        char_index     <= 5'd0;
                        byte_in_flight <= 1'b0;
                        state          <= STATE_SEND;
                    end
                    else begin
                        convert_count <= convert_count + 1'b1;
                    end
                end

                STATE_SEND: begin
                    if (!byte_in_flight && !uart_busy) begin
                        uart_data      <= packet_character(char_index);
                        uart_start     <= 1'b1;
                        byte_in_flight <= 1'b1;
                    end

                    if (uart_done) begin
                        byte_in_flight <= 1'b0;

                        if (char_index == 5'd22) begin
                            busy  <= 1'b0;
                            done  <= 1'b1;
                            state <= STATE_IDLE;
                        end
                        else begin
                            char_index <= char_index + 1'b1;
                        end
                    end
                end

                default: begin
                    state <= STATE_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule
