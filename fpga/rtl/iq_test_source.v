`timescale 1ns / 1ps

module iq_test_source (
    input  wire               clk,
    input  wire               reset,
    input  wire               start,

    // 00: 잡음·간섭만 존재
    // 01: 강한 목표 신호
    // 10: 약한 목표 신호 + 강한 잡음
    // 11: 목표 없이 강한 다른 주파수 간섭
    input  wire [1:0]         scenario,

    input  wire               sample_ready,

    output wire signed [15:0] sample_i,
    output wire signed [15:0] sample_q,

    output wire               sample_valid,
    output wire               sample_last,

    output reg                busy,
    output reg                done
);

    localparam integer FFT_LENGTH = 1024;

    (* rom_style = "block" *)
    reg [31:0] iq_memory_0 [0:FFT_LENGTH-1];

    (* rom_style = "block" *)
    reg [31:0] iq_memory_1 [0:FFT_LENGTH-1];

    (* rom_style = "block" *)
    reg [31:0] iq_memory_2 [0:FFT_LENGTH-1];

    (* rom_style = "block" *)
    reg [31:0] iq_memory_3 [0:FFT_LENGTH-1];


    reg [9:0]  sample_index;
    reg [31:0] sample_data;
    reg        valid_reg;

    // 전송 도중 스위치가 바뀌어도 현재 시나리오는 유지합니다.
    reg [1:0] scenario_latched;


    initial begin
        $readmemh(
            "iq_test_0.mem",
            iq_memory_0
        );

        $readmemh(
            "iq_test_1.mem",
            iq_memory_1
        );

        $readmemh(
            "iq_test_2.mem",
            iq_memory_2
        );

        $readmemh(
            "iq_test_3.mem",
            iq_memory_3
        );
    end


    assign sample_i =
        $signed(sample_data[15:0]);

    assign sample_q =
        $signed(sample_data[31:16]);

    assign sample_valid =
        valid_reg;

    assign sample_last =
        valid_reg
        &&
        (sample_index == 10'd1023);


    always @(posedge clk) begin

        // done은 한 클럭 펄스입니다.
        done <= 1'b0;

        if (reset) begin
            sample_index     <= 10'd0;
            sample_data      <= 32'd0;
            valid_reg        <= 1'b0;
            scenario_latched <= 2'b00;

            busy <= 1'b0;
            done <= 1'b0;
        end

        else begin

            // 새 FFT 입력 프레임 시작
            if (start && !busy) begin
                sample_index     <= 10'd0;
                scenario_latched <= scenario;
                valid_reg        <= 1'b1;
                busy             <= 1'b1;

                case (scenario)
                    2'b00:
                        sample_data <=
                            iq_memory_0[0];

                    2'b01:
                        sample_data <=
                            iq_memory_1[0];

                    2'b10:
                        sample_data <=
                            iq_memory_2[0];

                    2'b11:
                        sample_data <=
                            iq_memory_3[0];

                    default:
                        sample_data <=
                            32'd0;
                endcase
            end

            // valid와 ready가 모두 1일 때만 다음 샘플로 진행
            else if (
                valid_reg
                &&
                sample_ready
            ) begin

                // 1024번째 샘플 전달 완료
                if (sample_index == 10'd1023) begin
                    sample_index <= 10'd0;
                    valid_reg    <= 1'b0;
                    busy         <= 1'b0;
                    done         <= 1'b1;
                end

                else begin
                    sample_index <=
                        sample_index + 1'b1;

                    case (scenario_latched)
                        2'b00:
                            sample_data <=
                                iq_memory_0[
                                    sample_index + 1'b1
                                ];

                        2'b01:
                            sample_data <=
                                iq_memory_1[
                                    sample_index + 1'b1
                                ];

                        2'b10:
                            sample_data <=
                                iq_memory_2[
                                    sample_index + 1'b1
                                ];

                        2'b11:
                            sample_data <=
                                iq_memory_3[
                                    sample_index + 1'b1
                                ];

                        default:
                            sample_data <=
                                32'd0;
                    endcase
                end
            end
        end
    end

endmodule