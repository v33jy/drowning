`timescale 1ns / 1ps

module top (
    input  wire CLK100MHZ,
    input  wire BTNC,

    // SW0: 전체 리셋
    // SW2, SW1: 시험 시나리오 선택
    input  wire SW0,
    input  wire SW1,
    input  wire SW2,

    // LD0: 목표 신호 탐지 결과
    // LD1: FFT 분석 완료
    // LD2: FFT 인터페이스 오류
    output wire LD0,
    output wire LD1,
    output wire LD2
);

    // =====================================================
    // 전원 투입 초기화
    // =====================================================

    reg [4:0] power_on_count = 5'd0;

    always @(posedge CLK100MHZ) begin
        if (SW0) begin
            power_on_count <= 5'd0;
        end

        else if (power_on_count != 5'd31) begin
            power_on_count <=
                power_on_count + 1'b1;
        end
    end


    wire reset_internal;

    assign reset_internal =
        SW0
        ||
        (power_on_count != 5'd31);


    // =====================================================
    // 버튼 동기화 및 FFT 시작 제어
    // =====================================================

    reg btn_meta = 1'b0;
    reg btn_sync = 1'b0;
    reg btn_prev = 1'b0;

    reg start_pending = 1'b0;
    reg source_start  = 1'b0;

    wire config_done;
    wire source_busy;


    always @(posedge CLK100MHZ) begin

        if (reset_internal) begin
            btn_meta <= 1'b0;
            btn_sync <= 1'b0;
            btn_prev <= 1'b0;

            start_pending <= 1'b0;
            source_start  <= 1'b0;
        end

        else begin
            // 비동기 버튼을 클럭에 동기화
            btn_meta <= BTNC;
            btn_sync <= btn_meta;
            btn_prev <= btn_sync;

            // 시작 신호는 한 클럭 펄스
            source_start <= 1'b0;

            // 버튼 상승 에지 검출
            if (btn_sync && !btn_prev) begin
                start_pending <= 1'b1;
            end

            // FFT 설정이 끝났고 소스가 대기 중일 때 시작
            if (
                start_pending
                &&
                config_done
                &&
                !source_busy
            ) begin
                source_start  <= 1'b1;
                start_pending <= 1'b0;
            end
        end
    end


    // =====================================================
    // 복합 I/Q 시험 신호 발생기
    // =====================================================

    wire signed [15:0] source_i;
    wire signed [15:0] source_q;

    wire source_valid;
    wire source_ready;
    wire source_last;
    wire source_done;


    iq_test_source u_iq_test_source (
        .clk          (CLK100MHZ),
        .reset        (reset_internal),
        .start        (source_start),

        // SW2 SW1:
        // 00, 01, 10, 11
        .scenario     ({SW2, SW1}),

        .sample_ready (source_ready),

        .sample_i     (source_i),
        .sample_q     (source_q),
        .sample_valid (source_valid),
        .sample_last  (source_last),

        .busy         (source_busy),
        .done         (source_done)
    );


    // =====================================================
    // FFT Wrapper
    // =====================================================

    wire signed [15:0] fft_real;
    wire signed [15:0] fft_imag;

    wire [9:0] fft_bin;
    wire [7:0] fft_block_exp;

    wire fft_valid;
    wire fft_ready;
    wire fft_last;

    wire [7:0] status_block_exp;
    wire status_valid;

    wire frame_started;
    wire tlast_unexpected;
    wire tlast_missing;
    wire status_channel_halt;
    wire data_in_channel_halt;
    wire data_out_channel_halt;
    wire error_event;


    fft_wrapper u_fft_wrapper (
        .clk                   (CLK100MHZ),
        .reset                 (reset_internal),

        .sample_i              (source_i),
        .sample_q              (source_q),
        .sample_valid          (source_valid),
        .sample_last           (source_last),
        .sample_ready          (source_ready),

        .fft_real              (fft_real),
        .fft_imag              (fft_imag),
        .fft_bin               (fft_bin),
        .fft_block_exp         (fft_block_exp),
        .fft_valid             (fft_valid),
        .fft_last              (fft_last),
        .fft_ready             (fft_ready),

        .config_done           (config_done),

        .status_block_exp      (status_block_exp),
        .status_valid          (status_valid),

        .frame_started         (frame_started),
        .tlast_unexpected      (tlast_unexpected),
        .tlast_missing         (tlast_missing),
        .status_channel_halt   (status_channel_halt),
        .data_in_channel_halt  (data_in_channel_halt),
        .data_out_channel_halt (data_out_channel_halt),

        .error_event           (error_event)
    );


    // =====================================================
    // 스펙트럼 분석 및 목표 대역 탐지
    // =====================================================

    wire result_done;
    wire detected;

    wire [9:0]  peak_bin;
    wire [41:0] peak_power;
    wire [41:0] target_power;
    wire [41:0] noise_floor;

    wire [7:0] result_block_exp;


    spectrum_analyzer #(
        .TARGET_BIN        (10'd128),
        .INTERFERENCE_BIN  (10'd310),
        .BAND_HALF_WIDTH   (2),
        .DETECT_SHIFT      (5)
    ) u_spectrum_analyzer (
        .clk              (CLK100MHZ),
        .reset            (reset_internal),

        .fft_real         (fft_real),
        .fft_imag         (fft_imag),
        .fft_bin          (fft_bin),
        .fft_block_exp    (fft_block_exp),
        .fft_valid        (fft_valid),
        .fft_last         (fft_last),
        .fft_ready        (fft_ready),

        .result_done      (result_done),
        .detected         (detected),

        .peak_bin         (peak_bin),
        .peak_power       (peak_power),
        .target_power     (target_power),
        .noise_floor      (noise_floor),
        .result_block_exp (result_block_exp)
    );


    // =====================================================
    // LED 상태 저장
    // =====================================================

    reg result_seen   = 1'b0;
    reg error_latched = 1'b0;


    always @(posedge CLK100MHZ) begin

        if (reset_internal) begin
            result_seen   <= 1'b0;
            error_latched <= 1'b0;
        end

        else begin
            // 새 시험 시작 시 이전 상태 제거
            if (source_start) begin
                result_seen   <= 1'b0;
                error_latched <= 1'b0;
            end

            // FFT 분석 완료
            if (result_done) begin
                result_seen <= 1'b1;
            end

            // FFT 인터페이스 오류 저장
            if (error_event) begin
                error_latched <= 1'b1;
            end
        end
    end


    assign LD0 =
        detected;

    assign LD1 =
        result_seen;

    assign LD2 =
        error_latched;

endmodule