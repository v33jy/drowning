`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLOCK_HZ = 100_000_000,
    parameter integer BAUD_RATE = 115_200
)(
    input  wire       clk,
    input  wire       reset,
    input  wire       start,
    input  wire [7:0] data,
    output reg        tx,
    output reg        busy,
    output reg        done
);

    localparam integer CLKS_PER_BIT =
        (CLOCK_HZ + (BAUD_RATE / 2)) / BAUD_RATE;

    localparam integer CLOCK_COUNT_WIDTH = 16;

    reg [CLOCK_COUNT_WIDTH-1:0] clock_count;
    reg [3:0]                   bit_index;
    reg [9:0]                   frame;

    always @(posedge clk) begin
        done <= 1'b0;

        if (reset) begin
            tx          <= 1'b1;
            busy        <= 1'b0;
            done        <= 1'b0;
            clock_count <= {CLOCK_COUNT_WIDTH{1'b0}};
            bit_index   <= 4'd0;
            frame       <= 10'h3FF;
        end
        else begin
            if (!busy) begin
                tx          <= 1'b1;
                clock_count <= {CLOCK_COUNT_WIDTH{1'b0}};
                bit_index   <= 4'd0;

                if (start) begin
                    // {정지 비트, 데이터[7:0], 시작 비트}
                    frame <= {1'b1, data, 1'b0};
                    tx    <= 1'b0;
                    busy  <= 1'b1;
                end
            end
            else begin
                if (clock_count == CLKS_PER_BIT - 1) begin
                    clock_count <= {CLOCK_COUNT_WIDTH{1'b0}};

                    if (bit_index == 4'd9) begin
                        tx    <= 1'b1;
                        busy  <= 1'b0;
                        done  <= 1'b1;
                    end
                    else begin
                        bit_index <= bit_index + 1'b1;
                        tx        <= frame[bit_index + 1'b1];
                    end
                end
                else begin
                    clock_count <= clock_count + 1'b1;
                end
            end
        end
    end

endmodule
