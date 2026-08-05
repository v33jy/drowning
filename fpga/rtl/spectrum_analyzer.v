`timescale 1ns / 1ps

module spectrum_analyzer #(
    // 시험 데이터의 목표 신호와 간섭 신호 위치
    parameter [9:0] TARGET_BIN       = 10'd128,
    parameter [9:0] INTERFERENCE_BIN = 10'd310,

    // 중심 bin을 기준으로 ±2 bin을 하나의 대역으로 사용
    parameter integer BAND_HALF_WIDTH = 2,

    /*
     * 판정 조건:
     *
     * 목표 대역 전력 합 >
     * 잡음 바닥 × 32
     *
     * 목표 대역이 5개 bin이므로,
     * bin당 평균으로 보면 대략 잡음의 6.4배 이상입니다.
     */
    parameter integer DETECT_SHIFT = 5
)(
    input  wire                    clk,
    input  wire                    reset,

    // fft_wrapper에서 들어오는 FFT 결과
    input  wire signed [15:0]      fft_real,
    input  wire signed [15:0]      fft_imag,
    input  wire [9:0]              fft_bin,
    input  wire [7:0]              fft_block_exp,
    input  wire                    fft_valid,
    input  wire                    fft_last,

    // 현재 분석기는 매 클럭 결과를 받을 수 있음
    output wire                    fft_ready,

    // 한 프레임 분석 결과
    output reg                     result_done,
    output reg                     detected,

    output reg [9:0]               peak_bin,
    output reg [41:0]              peak_power,

    output reg [41:0]              target_power,
    output reg [41:0]              noise_floor,

    output reg [7:0]               result_block_exp
);

    // =====================================================
    // 목표 대역과 간섭 대역 범위
    // =====================================================

    localparam [9:0] TARGET_LOW =
        TARGET_BIN - BAND_HALF_WIDTH;

    localparam [9:0] TARGET_HIGH =
        TARGET_BIN + BAND_HALF_WIDTH;

    localparam [9:0] INTERFERENCE_LOW =
        INTERFERENCE_BIN - BAND_HALF_WIDTH;

    localparam [9:0] INTERFERENCE_HIGH =
        INTERFERENCE_BIN + BAND_HALF_WIDTH;


    wire in_target_band;

    assign in_target_band =
        (fft_bin >= TARGET_LOW) &&
        (fft_bin <= TARGET_HIGH);


    wire in_interference_band;

    assign in_interference_band =
        (fft_bin >= INTERFERENCE_LOW) &&
        (fft_bin <= INTERFERENCE_HIGH);


    /*
     * DC bin 0, 목표 대역, 시험용 간섭 대역은
     * 잡음 바닥 계산에서 제외합니다.
     */
    wire include_in_noise;

    assign include_in_noise =
        (fft_bin != 10'd0) &&
        !in_target_band &&
        !in_interference_band;


    // =====================================================
    // 복소 FFT 전력 계산
    //
    // power = real² + imag²
    // =====================================================

    wire [31:0] real_squared;
    wire [31:0] imag_squared;

    assign real_squared =
        fft_real * fft_real;

    assign imag_squared =
        fft_imag * fft_imag;


    wire [32:0] magnitude_squared;

    assign magnitude_squared =
        {1'b0, real_squared}
        +
        {1'b0, imag_squared};


    // 누산기 폭에 맞춰 42비트로 확장
    wire [41:0] magnitude_extended;

    assign magnitude_extended = {
        9'd0,
        magnitude_squared
    };


    // =====================================================
    // 프레임 내부 누산 레지스터
    // =====================================================

    reg [41:0] target_accumulator;
    reg [41:0] noise_accumulator;

    reg [41:0] peak_accumulator;
    reg [9:0]  peak_bin_accumulator;


    // 현재 FFT 결과까지 포함한 다음 값
    wire [41:0] next_target_accumulator;

    assign next_target_accumulator =
        target_accumulator
        +
        (
            in_target_band
            ? magnitude_extended
            : 42'd0
        );


    wire [41:0] next_noise_accumulator;

    assign next_noise_accumulator =
        noise_accumulator
        +
        (
            include_in_noise
            ? magnitude_extended
            : 42'd0
        );


    /*
     * 1024로 나눠 잡음 bin 하나당 평균값을 근사합니다.
     *
     * 실제 포함된 잡음 bin 수는 1024보다 조금 작지만,
     * 현재는 하드웨어를 단순화하기 위해 2^10으로 나눕니다.
     */
    wire [41:0] calculated_noise_floor;

    assign calculated_noise_floor =
        next_noise_accumulator >> 10;


    // =====================================================
    // 전체 스펙트럼 최대 피크
    // =====================================================

    wire current_is_new_peak;

    assign current_is_new_peak =
        (fft_bin != 10'd0) &&
        (magnitude_extended > peak_accumulator);


    wire [41:0] next_peak_power;

    assign next_peak_power =
        current_is_new_peak
        ? magnitude_extended
        : peak_accumulator;


    wire [9:0] next_peak_bin;

    assign next_peak_bin =
        current_is_new_peak
        ? fft_bin
        : peak_bin_accumulator;


    // =====================================================
    // 목표 신호 탐지 조건
    // =====================================================

    /*
     * 비교 중 왼쪽 시프트에 의한 비트 손실을 막기 위해
     * 47비트로 확장합니다.
     */
    wire [46:0] target_power_extended;
    wire [46:0] detection_threshold;

    assign target_power_extended = {
        5'd0,
        next_target_accumulator
    };

    assign detection_threshold =
        (
            {
                5'd0,
                calculated_noise_floor
            }
            << DETECT_SHIFT
        );


    wire next_detected;

    assign next_detected =
        target_power_extended >
        detection_threshold;


    // 분석기가 항상 FFT 데이터를 받을 준비가 된 상태
    assign fft_ready = 1'b1;


    // =====================================================
    // 순차 처리
    // =====================================================

    always @(posedge clk) begin

        // 결과 완료 신호는 한 클럭만 유지
        result_done <= 1'b0;

        if (reset) begin

            target_accumulator   <= 42'd0;
            noise_accumulator    <= 42'd0;

            peak_accumulator     <= 42'd0;
            peak_bin_accumulator <= 10'd0;

            result_done          <= 1'b0;
            detected             <= 1'b0;

            peak_bin             <= 10'd0;
            peak_power           <= 42'd0;

            target_power         <= 42'd0;
            noise_floor          <= 42'd0;

            result_block_exp     <= 8'd0;
        end

        else if (fft_valid) begin

            /*
             * TLAST가 들어오면 현재 샘플까지 포함한 값으로
             * 한 프레임 결과를 확정합니다.
             */
            if (fft_last) begin

                detected         <= next_detected;

                peak_bin         <= next_peak_bin;
                peak_power       <= next_peak_power;

                target_power     <=
                    next_target_accumulator;

                noise_floor      <=
                    calculated_noise_floor;

                result_block_exp <=
                    fft_block_exp;

                result_done      <= 1'b1;


                // 다음 FFT 프레임을 위해 초기화
                target_accumulator   <= 42'd0;
                noise_accumulator    <= 42'd0;

                peak_accumulator     <= 42'd0;
                peak_bin_accumulator <= 10'd0;
            end

            else begin

                target_accumulator <=
                    next_target_accumulator;

                noise_accumulator <=
                    next_noise_accumulator;

                peak_accumulator <=
                    next_peak_power;

                peak_bin_accumulator <=
                    next_peak_bin;
            end
        end
    end

endmodule