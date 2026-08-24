`timescale 1ns / 1ps

module top (
    input  wire CLK100MHZ,
    input  wire SW0,          // 1 = 전체 리셋
    input  wire BTNC,         // 수동 통신 경로 테스트 패킷 1회 발생

    // Raspberry Pi SPI0, MODE0, 최대 20 MHz
    input  wire SPI_SCLK,
    input  wire SPI_MOSI,
    input  wire SPI_CS_N,

    output wire LD0,          // 안정화된 실제 탐지 상태
    output wire LD1,          // FFT 처리 heartbeat
    output wire LD2,          // 입력/FFT 오류 저장

    output wire UART_TX,      // Basys 3 USB-UART -> 노트북
    output wire PMOD_TX       // JA1 -> 드론 ESP32 GPIO4
);

    // 실제 시연용 보고 주기
    // DET 상태 변화는 가능한 즉시 전송하고, 상태가 유지되면 주기적으로 재보고합니다.
    localparam integer DET_REPORT_INTERVAL_CYCLES   = 50_000_000;   // 0.5 s
    localparam integer IDLE_REPORT_INTERVAL_CYCLES  = 100_000_000;  // 1.0 s
    localparam integer BUTTON_LOCKOUT_CYCLES        = 5_000_000;    // 50 ms

    // 단일 FFT 프레임의 순간 판정을 그대로 내보내지 않고 누적 점수로 안정화합니다.
    // 약 500 FFT frame/s 기준: 6회의 누적 탐지면 약 12 ms 수준입니다.
    localparam [3:0] DETECT_SCORE_MAX    = 4'd15;
    localparam [3:0] DETECT_ASSERT_SCORE = 4'd6;
    localparam [3:0] DETECT_CLEAR_SCORE  = 4'd2;

    // -----------------------------------------------------
    // 전원 인가 직후 짧은 내부 리셋
    // -----------------------------------------------------
    reg [7:0] power_on_count = 8'd0;
    always @(posedge CLK100MHZ) begin
        if (SW0)
            power_on_count <= 8'd0;
        else if (power_on_count != 8'hFF)
            power_on_count <= power_on_count + 1'b1;
    end

    wire reset_internal;
    assign reset_internal = SW0 || (power_on_count != 8'hFF);

    // -----------------------------------------------------
    // BTNC 동기화 + bounce lockout
    // -----------------------------------------------------
    reg [1:0]  btn_sync;
    reg        btn_prev;
    reg [22:0] btn_lockout;
    reg        manual_test_pulse;

    always @(posedge CLK100MHZ) begin
        if (reset_internal) begin
            btn_sync          <= 2'b00;
            btn_prev          <= 1'b0;
            btn_lockout       <= 23'd0;
            manual_test_pulse <= 1'b0;
        end
        else begin
            btn_sync <= {btn_sync[0], BTNC};
            manual_test_pulse <= 1'b0;

            if (btn_lockout != 0)
                btn_lockout <= btn_lockout - 1'b1;

            if (btn_sync[1] && !btn_prev && (btn_lockout == 0)) begin
                manual_test_pulse <= 1'b1;
                btn_lockout <= BUTTON_LOCKOUT_CYCLES - 1;
            end

            btn_prev <= btn_sync[1];
        end
    end

    // -----------------------------------------------------
    // Raspberry Pi SPI -> I/Q source
    // -----------------------------------------------------
    wire signed [15:0] source_i;
    wire signed [15:0] source_q;
    wire source_valid;
    wire source_ready;
    wire source_last;
    wire [9:0] target_bin_cfg;
    wire [3:0] detect_shift_cfg;
    wire detect_any_peak_cfg;
    wire packet_seen;
    wire input_overflow;
    wire protocol_error;

    spi_iq_source u_spi_iq_source (
        .clk                    (CLK100MHZ),
        .reset                  (reset_internal),
        .spi_sclk               (SPI_SCLK),
        .spi_mosi               (SPI_MOSI),
        .spi_cs_n               (SPI_CS_N),
        .sample_ready           (source_ready),
        .sample_i               (source_i),
        .sample_q               (source_q),
        .sample_valid           (source_valid),
        .sample_last            (source_last),
        .target_bin_cfg         (target_bin_cfg),
        .detect_shift_cfg       (detect_shift_cfg),
        .detect_any_peak_cfg    (detect_any_peak_cfg),
        .packet_seen            (packet_seen),
        .overflow_latched       (input_overflow),
        .protocol_error_latched (protocol_error)
    );

    // -----------------------------------------------------
    // 1024-point FFT
    // -----------------------------------------------------
    wire signed [15:0] fft_real;
    wire signed [15:0] fft_imag;
    wire [9:0] fft_bin;
    wire [7:0] fft_block_exp;
    wire fft_valid;
    wire fft_ready;
    wire fft_last;
    wire config_done;
    wire [7:0] status_block_exp;
    wire status_valid;
    wire frame_started;
    wire tlast_unexpected;
    wire tlast_missing;
    wire status_channel_halt;
    wire data_in_channel_halt;
    wire data_out_channel_halt;
    wire fft_error_event;

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
        .error_event           (fft_error_event)
    );

    // -----------------------------------------------------
    // 단일 FFT 프레임 분석
    // - 1 MS/s, 1024 FFT에서 bin 간격은 약 976.6 Hz
    // - BAND_HALF_WIDTH=72이면 target_bin 주변 약 ±70.3 kHz
    //   (총 약 141.6 kHz) 대역을 분석하므로 125 kHz LoRa 비콘을 포함합니다.
    // -----------------------------------------------------
    wire raw_result_done;
    wire raw_detected;
    wire [9:0] raw_peak_bin;
    wire [41:0] raw_peak_power;
    wire [41:0] raw_target_power;
    wire [41:0] raw_noise_floor;
    wire [7:0] raw_result_block_exp;

    spectrum_analyzer_runtime #(
        .BAND_HALF_WIDTH (72)
    ) u_spectrum_analyzer (
        .clk                  (CLK100MHZ),
        .reset                (reset_internal),
        .fft_real             (fft_real),
        .fft_imag             (fft_imag),
        .fft_bin              (fft_bin),
        .fft_block_exp        (fft_block_exp),
        .fft_valid            (fft_valid),
        .fft_last             (fft_last),
        .fft_ready            (fft_ready),
        .target_bin_cfg       (target_bin_cfg),
        .detect_shift_cfg     (detect_shift_cfg),
        .detect_any_peak_cfg  (detect_any_peak_cfg),
        .result_done          (raw_result_done),
        .detected             (raw_detected),
        .peak_bin             (raw_peak_bin),
        .peak_power           (raw_peak_power),
        .target_power         (raw_target_power),
        .noise_floor          (raw_noise_floor),
        .result_block_exp     (raw_result_block_exp)
    );

    // -----------------------------------------------------
    // 실제 환경용 시간축 안정화
    // - raw DET=1이면 점수 +1, DET=0이면 -1
    // - 점수 >= 6에서 DET=1 확정
    // - 점수 <= 2에서 DET=0 해제 (hysteresis)
    // - 순간 잡음에 의한 0/1 튐을 줄입니다.
    // -----------------------------------------------------
    reg [3:0] detect_score;
    reg       stable_detected;
    reg [9:0] stable_peak_bin;
    reg [41:0] stable_peak_power;
    reg [9:0] latest_raw_peak_bin;
    reg [41:0] latest_raw_peak_power;
    reg        have_result;

    reg [7:0] heartbeat_frame_count;
    reg       heartbeat;
    reg       error_latched;

    always @(posedge CLK100MHZ) begin
        if (reset_internal) begin
            detect_score          <= 4'd0;
            stable_detected       <= 1'b0;
            stable_peak_bin       <= 10'd0;
            stable_peak_power     <= 42'd0;
            latest_raw_peak_bin   <= 10'd0;
            latest_raw_peak_power <= 42'd0;
            have_result           <= 1'b0;
            heartbeat_frame_count <= 8'd0;
            heartbeat             <= 1'b0;
            error_latched         <= 1'b0;
        end
        else begin
            if (raw_result_done) begin
                have_result           <= 1'b1;
                latest_raw_peak_bin   <= raw_peak_bin;
                latest_raw_peak_power <= raw_peak_power;

                // 약 256개 FFT 결과마다 LED 토글: 약 500 frame/s일 때 약 0.5초 주기.
                if (heartbeat_frame_count == 8'hFF) begin
                    heartbeat_frame_count <= 8'd0;
                    heartbeat <= ~heartbeat;
                end
                else begin
                    heartbeat_frame_count <= heartbeat_frame_count + 1'b1;
                end

                if (raw_detected) begin
                    if (detect_score < DETECT_SCORE_MAX)
                        detect_score <= detect_score + 1'b1;

                    // 안정화 DET가 켜지는 순간의 실제 피크를 보존합니다.
                    if (!stable_detected && (detect_score >= (DETECT_ASSERT_SCORE - 1'b1))) begin
                        stable_detected   <= 1'b1;
                        stable_peak_bin   <= raw_peak_bin;
                        stable_peak_power <= raw_peak_power;
                    end
                    else if (stable_detected && (raw_peak_power >= stable_peak_power)) begin
                        // DET=1 유지 중에는 가장 강했던 피크를 보존합니다.
                        stable_peak_bin   <= raw_peak_bin;
                        stable_peak_power <= raw_peak_power;
                    end
                end
                else begin
                    if (detect_score != 0)
                        detect_score <= detect_score - 1'b1;

                    if (stable_detected && (detect_score <= (DETECT_CLEAR_SCORE + 1'b1))) begin
                        stable_detected   <= 1'b0;
                        // DET=0 보고에도 최신 실제 스펙트럼 정보를 남깁니다.
                        stable_peak_bin   <= raw_peak_bin;
                        stable_peak_power <= raw_peak_power;
                    end
                end
            end

            if (fft_error_event || input_overflow || protocol_error)
                error_latched <= 1'b1;
        end
    end

    // -----------------------------------------------------
    // UART 보고 스케줄러
    // - DET 상태가 바뀌면 즉시 보고
    // - DET=1 유지 시 0.5초마다 재보고
    // - DET=0 유지 시 1초마다 상태 보고
    // - BTNC는 통신 경로만 확인하는 고정 테스트 패킷
    // -----------------------------------------------------
    reg [26:0] report_counter;
    reg        last_reported_detected;
    reg        have_reported_state;
    reg        manual_result_pending;
    reg        packet_start;

    reg        packet_detected;
    reg [9:0]  packet_peak_bin;
    reg [41:0] packet_peak_power;

    wire packet_busy;
    wire packet_done;

    wire [26:0] active_report_interval;
    assign active_report_interval = stable_detected
        ? DET_REPORT_INTERVAL_CYCLES
        : IDLE_REPORT_INTERVAL_CYCLES;

    always @(posedge CLK100MHZ) begin
        if (reset_internal) begin
            report_counter        <= 27'd0;
            last_reported_detected <= 1'b0;
            have_reported_state   <= 1'b0;
            manual_result_pending <= 1'b0;
            packet_start          <= 1'b0;
            packet_detected       <= 1'b0;
            packet_peak_bin       <= 10'd0;
            packet_peak_power     <= 42'd0;
        end
        else begin
            packet_start <= 1'b0;

            if (report_counter < IDLE_REPORT_INTERVAL_CYCLES)
                report_counter <= report_counter + 1'b1;

            if (manual_test_pulse)
                manual_result_pending <= 1'b1;

            if (manual_result_pending && !packet_busy) begin
                packet_detected       <= 1'b1;
                packet_peak_bin       <= 10'd512;
                packet_peak_power     <= (42'd12345 << 10);
                packet_start          <= 1'b1;
                manual_result_pending <= 1'b0;
            end
            else if (
                have_result &&
                !packet_busy &&
                (!have_reported_state || (stable_detected != last_reported_detected))
            ) begin
                packet_detected       <= stable_detected;
                packet_peak_bin       <= stable_detected ? stable_peak_bin   : latest_raw_peak_bin;
                packet_peak_power     <= stable_detected ? stable_peak_power : latest_raw_peak_power;
                packet_start          <= 1'b1;
                last_reported_detected <= stable_detected;
                have_reported_state   <= 1'b1;
                report_counter        <= 27'd0;
            end
            else if (
                have_result &&
                !packet_busy &&
                have_reported_state &&
                (report_counter >= (active_report_interval - 1'b1))
            ) begin
                packet_detected       <= stable_detected;
                packet_peak_bin       <= stable_detected ? stable_peak_bin   : latest_raw_peak_bin;
                packet_peak_power     <= stable_detected ? stable_peak_power : latest_raw_peak_power;
                packet_start          <= 1'b1;
                last_reported_detected <= stable_detected;
                report_counter        <= 27'd0;
            end
        end
    end

    wire uart_serial_tx;
    det_packet_tx #(
        .CLOCK_HZ  (100_000_000),
        .BAUD_RATE (115_200)
    ) u_det_packet_tx (
        .clk        (CLK100MHZ),
        .reset      (reset_internal),
        .start      (packet_start),
        .detected   (packet_detected),
        .peak_bin   (packet_peak_bin),
        .peak_power (packet_peak_power),
        .tx         (uart_serial_tx),
        .busy       (packet_busy),
        .done       (packet_done)
    );

    // 같은 UART 스트림을 노트북 디버깅과 ESP32 직결에 동시에 출력합니다.
    assign UART_TX = uart_serial_tx;
    assign PMOD_TX = uart_serial_tx;

    assign LD0 = stable_detected;
    assign LD1 = heartbeat;
    assign LD2 = error_latched;

endmodule
