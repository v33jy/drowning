`timescale 1ns / 1ps

/*
 * 1024-point FFT 스펙트럼 분석기.
 *
 * detect_any_peak_cfg = 1:
 *   DC를 제외한 전체 스펙트럼의 최대 peak를 noise 평균과 비교합니다.
 *
 * detect_any_peak_cfg = 0:
 *   target_bin_cfg ± BAND_HALF_WIDTH 대역의 "평균 전력"을
 *   타깃 대역 밖 noise 평균과 비교합니다.
 *   target_sum * noise_count > noise_sum * target_count * 2^detect_shift
 *   방식으로 비교하므로 대역폭이 넓은 LoRa chirp도 단일-bin peak보다
 *   안정적으로 검출할 수 있습니다.
 */
module spectrum_analyzer_runtime #(
    parameter integer BAND_HALF_WIDTH = 72
)(
    input  wire                    clk,
    input  wire                    reset,

    input  wire signed [15:0]      fft_real,
    input  wire signed [15:0]      fft_imag,
    input  wire [9:0]              fft_bin,
    input  wire [7:0]              fft_block_exp,
    input  wire                    fft_valid,
    input  wire                    fft_last,
    output wire                    fft_ready,

    input  wire [9:0]              target_bin_cfg,
    input  wire [3:0]              detect_shift_cfg,
    input  wire                    detect_any_peak_cfg,

    output reg                     result_done,
    output reg                     detected,
    output reg [9:0]               peak_bin,
    output reg [41:0]              peak_power,
    output reg [41:0]              target_power,
    output reg [41:0]              noise_floor,
    output reg [7:0]               result_block_exp
);

    reg [9:0] target_bin_latched;
    reg [3:0] detect_shift_latched;
    reg       detect_any_peak_latched;

    wire [9:0] target_low;
    wire [9:0] target_high;
    assign target_low =
        (target_bin_latched < BAND_HALF_WIDTH)
        ? 10'd0
        : target_bin_latched - BAND_HALF_WIDTH;

    assign target_high =
        (target_bin_latched > (10'd1023 - BAND_HALF_WIDTH))
        ? 10'd1023
        : target_bin_latched + BAND_HALF_WIDTH;

    wire in_target_band;
    assign in_target_band =
        (fft_bin >= target_low) &&
        (fft_bin <= target_high);

    wire include_in_noise;
    assign include_in_noise = (fft_bin != 10'd0) && !in_target_band;

    wire [31:0] real_squared;
    wire [31:0] imag_squared;
    wire [32:0] magnitude_squared;
    wire [41:0] magnitude_extended;

    assign real_squared = fft_real * fft_real;
    assign imag_squared = fft_imag * fft_imag;
    assign magnitude_squared = {1'b0, real_squared} + {1'b0, imag_squared};
    assign magnitude_extended = {9'd0, magnitude_squared};

    reg [41:0] target_sum_acc;
    reg [41:0] noise_sum_acc;
    reg [10:0] target_count_acc;
    reg [10:0] noise_count_acc;
    reg [41:0] global_peak_acc;
    reg [9:0]  global_peak_bin_acc;
    reg [41:0] target_peak_acc;
    reg [9:0]  target_peak_bin_acc;

    wire [41:0] next_target_sum;
    wire [41:0] next_noise_sum;
    wire [10:0] next_target_count;
    wire [10:0] next_noise_count;
    wire [41:0] next_global_peak;
    wire [9:0]  next_global_peak_bin;
    wire [41:0] next_target_peak;
    wire [9:0]  next_target_peak_bin;

    assign next_target_sum = target_sum_acc +
        (in_target_band ? magnitude_extended : 42'd0);

    assign next_noise_sum = noise_sum_acc +
        (include_in_noise ? magnitude_extended : 42'd0);

    assign next_target_count = target_count_acc + (in_target_band ? 11'd1 : 11'd0);
    assign next_noise_count  = noise_count_acc  + (include_in_noise ? 11'd1 : 11'd0);

    assign next_global_peak =
        ((fft_bin != 10'd0) && (magnitude_extended > global_peak_acc))
        ? magnitude_extended : global_peak_acc;

    assign next_global_peak_bin =
        ((fft_bin != 10'd0) && (magnitude_extended > global_peak_acc))
        ? fft_bin : global_peak_bin_acc;

    assign next_target_peak =
        (in_target_band && (magnitude_extended > target_peak_acc))
        ? magnitude_extended : target_peak_acc;

    assign next_target_peak_bin =
        (in_target_band && (magnitude_extended > target_peak_acc))
        ? fft_bin : target_peak_bin_acc;

    // 전체 peak 모드용 noise 평균 근사(1024 = 2^10).
    wire [41:0] calculated_noise_floor;
    assign calculated_noise_floor = next_noise_sum >> 10;

    wire [56:0] any_peak_threshold;
    assign any_peak_threshold = ({15'd0, calculated_noise_floor} << detect_shift_latched);

    wire next_detected_any;
    assign next_detected_any = {15'd0, next_global_peak} > any_peak_threshold;

    // 대역 평균 전력 비교. 나눗셈 대신 교차곱으로 정확히 비교합니다.
    wire [52:0] target_norm;
    wire [52:0] noise_norm;
    wire [67:0] noise_norm_threshold;
    assign target_norm = next_target_sum * next_noise_count;
    assign noise_norm  = next_noise_sum  * next_target_count;
    assign noise_norm_threshold = ({15'd0, noise_norm} << detect_shift_latched);

    wire next_detected_target;
    assign next_detected_target =
        (next_target_count != 0) &&
        (next_noise_count != 0) &&
        ({15'd0, target_norm} > noise_norm_threshold);

    assign fft_ready = 1'b1;

    always @(posedge clk) begin
        result_done <= 1'b0;

        if (reset) begin
            target_bin_latched       <= 10'd256;
            detect_shift_latched     <= 4'd1;
            detect_any_peak_latched  <= 1'b0;

            target_sum_acc           <= 42'd0;
            noise_sum_acc            <= 42'd0;
            target_count_acc         <= 11'd0;
            noise_count_acc          <= 11'd0;
            global_peak_acc          <= 42'd0;
            global_peak_bin_acc      <= 10'd0;
            target_peak_acc          <= 42'd0;
            target_peak_bin_acc      <= 10'd0;

            detected                 <= 1'b0;
            peak_bin                 <= 10'd0;
            peak_power               <= 42'd0;
            target_power             <= 42'd0;
            noise_floor              <= 42'd0;
            result_block_exp         <= 8'd0;
        end
        else if (fft_valid) begin
            if (fft_bin == 10'd0) begin
                target_bin_latched      <= target_bin_cfg;
                detect_shift_latched    <= detect_shift_cfg;
                detect_any_peak_latched <= detect_any_peak_cfg;
            end

            if (fft_last) begin
                detected <= detect_any_peak_latched
                    ? next_detected_any
                    : next_detected_target;

                peak_bin <= detect_any_peak_latched
                    ? next_global_peak_bin
                    : next_target_peak_bin;

                peak_power <= detect_any_peak_latched
                    ? next_global_peak
                    : next_target_peak;

                target_power     <= next_target_sum;
                noise_floor      <= calculated_noise_floor;
                result_block_exp <= fft_block_exp;
                result_done      <= 1'b1;

                target_sum_acc      <= 42'd0;
                noise_sum_acc       <= 42'd0;
                target_count_acc    <= 11'd0;
                noise_count_acc     <= 11'd0;
                global_peak_acc     <= 42'd0;
                global_peak_bin_acc <= 10'd0;
                target_peak_acc     <= 42'd0;
                target_peak_bin_acc <= 10'd0;
            end
            else begin
                target_sum_acc      <= next_target_sum;
                noise_sum_acc       <= next_noise_sum;
                target_count_acc    <= next_target_count;
                noise_count_acc     <= next_noise_count;
                global_peak_acc     <= next_global_peak;
                global_peak_bin_acc <= next_global_peak_bin;
                target_peak_acc     <= next_target_peak;
                target_peak_bin_acc <= next_target_peak_bin;
            end
        end
    end
endmodule
