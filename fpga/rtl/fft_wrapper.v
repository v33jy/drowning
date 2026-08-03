`timescale 1ns / 1ps

module fft_wrapper (
    input  wire clk,

    /*
     * reset = 1이면 Wrapper와 FFT IP를 초기화합니다.
     * FFT IP의 aresetn은 active-low이므로 내부에서 반전합니다.
     */
    input  wire reset,

    // =====================================================
    // 복소 I/Q 입력
    // =====================================================

    input  wire signed [15:0] sample_i,
    input  wire signed [15:0] sample_q,

    input  wire               sample_valid,
    input  wire               sample_last,

    /*
     * sample_valid와 sample_ready가 동시에 1인 클럭에서
     * 입력 샘플 하나가 FFT IP로 전달됩니다.
     */
    output wire               sample_ready,

    // =====================================================
    // 복소 FFT 출력
    // =====================================================

    output wire signed [15:0] fft_real,
    output wire signed [15:0] fft_imag,

    // 1024-point FFT이므로 bin 번호는 0~1023
    output wire [9:0]         fft_bin,

    // Block Floating Point의 프레임 스케일 값
    output wire [7:0]         fft_block_exp,

    output wire               fft_valid,
    output wire               fft_last,

    /*
     * spectrum_analyzer가 FFT 출력을 받을 준비가 되었을 때 1
     */
    input  wire               fft_ready,

    // =====================================================
    // FFT 설정 및 상태 출력
    // =====================================================

    output reg                config_done,

    output wire [7:0]         status_block_exp,
    output wire               status_valid,

    // FFT IP 이벤트 신호
    output wire               frame_started,
    output wire               tlast_unexpected,
    output wire               tlast_missing,
    output wire               status_channel_halt,
    output wire               data_in_channel_halt,
    output wire               data_out_channel_halt,

    // 주요 오류 이벤트를 하나로 묶은 신호
    output wire               error_event
);

    // =====================================================
    // FFT 설정 채널
    // =====================================================

    /*
     * s_axis_config_tdata[0] = FWD_INV
     *
     * 1: Forward FFT
     * 0: Inverse FFT
     *
     * FFT 길이는 IP에서 1024로 고정되어 있으므로
     * 현재 설정 데이터에서는 bit 0만 사용합니다.
     */
    wire [7:0] config_data;

    assign config_data =
        8'b0000_0001;


    reg  config_valid;
    wire config_ready;


    /*
     * 리셋이 끝나면 설정 데이터를 한 번 전송합니다.
     *
     * config_valid와 config_ready가 동시에 1이 된 클럭에서
     * FFT IP가 설정값을 수락한 것입니다.
     */
    always @(posedge clk) begin

        if (reset) begin
            config_valid <= 1'b1;
            config_done  <= 1'b0;
        end

        else begin

            if (
                config_valid
                &&
                config_ready
            ) begin
                config_valid <= 1'b0;
                config_done  <= 1'b1;
            end
        end
    end


    // =====================================================
    // FFT 입력 AXI4-Stream
    // =====================================================

    wire [31:0] fft_input_data;
    wire        fft_input_valid;
    wire        fft_input_ready;
    wire        fft_input_last;


    /*
     * FFT 입력 TDATA 구성
     *
     * [15:0]  = 실수부 I
     * [31:16] = 허수부 Q
     */
    assign fft_input_data = {
        sample_q,
        sample_i
    };


    /*
     * FFT 설정이 완료된 후에만 입력 데이터를 전달합니다.
     */
    assign fft_input_valid =
        config_done
        &&
        sample_valid;


    assign fft_input_last =
        sample_last;


    /*
     * 설정 완료 전에는 입력 소스가 진행하지 못하게 합니다.
     */
    assign sample_ready =
        config_done
        &&
        fft_input_ready;


    // =====================================================
    // FFT 출력 AXI4-Stream
    // =====================================================

    wire [31:0] fft_output_data;
    wire [23:0] fft_output_user;

    wire fft_output_valid;
    wire fft_output_ready;
    wire fft_output_last;


    /*
     * FFT 출력 TDATA 구성
     *
     * [15:0]  = FFT 실수부
     * [31:16] = FFT 허수부
     */
    assign fft_real =
        $signed(
            fft_output_data[15:0]
        );


    assign fft_imag =
        $signed(
            fft_output_data[31:16]
        );


    /*
     * FFT 출력 TUSER 구성
     *
     * [9:0]   = XK_INDEX
     * [15:10] = 패딩
     * [23:16] = BLK_EXP
     */
    assign fft_bin =
        fft_output_user[9:0];


    assign fft_block_exp =
        fft_output_user[23:16];


    assign fft_valid =
        fft_output_valid;


    assign fft_last =
        fft_output_last;


    assign fft_output_ready =
        fft_ready;


    // =====================================================
    // FFT 상태 채널
    // =====================================================

    wire [7:0] fft_status_data;
    wire       fft_status_valid;


    /*
     * Block Floating Point 사용 시 상태 채널에는
     * 해당 프레임의 BLK_EXP가 전달됩니다.
     */
    assign status_block_exp =
        fft_status_data;


    assign status_valid =
        fft_status_valid;


    // =====================================================
    // FFT 이벤트 오류 통합
    // =====================================================

    assign error_event =
        tlast_unexpected
        ||
        tlast_missing
        ||
        status_channel_halt
        ||
        data_in_channel_halt
        ||
        data_out_channel_halt;


    // =====================================================
    // AMD FFT IP 인스턴스
    // =====================================================

    xfft_1024 u_xfft_1024 (
        // 클럭
        .aclk(
            clk
        ),

        /*
         * FFT IP reset은 active-low입니다.
         * 외부 reset이 1이면 aresetn은 0이 됩니다.
         */
        .aresetn(
            ~reset
        ),

        // -------------------------------------------------
        // 설정 채널
        // -------------------------------------------------

        .s_axis_config_tdata(
            config_data
        ),

        .s_axis_config_tvalid(
            config_valid
        ),

        .s_axis_config_tready(
            config_ready
        ),

        // -------------------------------------------------
        // 입력 데이터 채널
        // -------------------------------------------------

        .s_axis_data_tdata(
            fft_input_data
        ),

        .s_axis_data_tvalid(
            fft_input_valid
        ),

        .s_axis_data_tready(
            fft_input_ready
        ),

        .s_axis_data_tlast(
            fft_input_last
        ),

        // -------------------------------------------------
        // 출력 데이터 채널
        // -------------------------------------------------

        .m_axis_data_tdata(
            fft_output_data
        ),

        .m_axis_data_tuser(
            fft_output_user
        ),

        .m_axis_data_tvalid(
            fft_output_valid
        ),

        .m_axis_data_tready(
            fft_output_ready
        ),

        .m_axis_data_tlast(
            fft_output_last
        ),

        // -------------------------------------------------
        // 상태 채널
        // -------------------------------------------------

        .m_axis_status_tdata(
            fft_status_data
        ),

        .m_axis_status_tvalid(
            fft_status_valid
        ),

        /*
         * 상태 데이터는 항상 즉시 받도록 설정합니다.
         */
        .m_axis_status_tready(
            1'b1
        ),

        // -------------------------------------------------
        // 이벤트 출력
        // -------------------------------------------------

        .event_frame_started(
            frame_started
        ),

        .event_tlast_unexpected(
            tlast_unexpected
        ),

        .event_tlast_missing(
            tlast_missing
        ),

        .event_status_channel_halt(
            status_channel_halt
        ),

        .event_data_in_channel_halt(
            data_in_channel_halt
        ),

        .event_data_out_channel_halt(
            data_out_channel_halt
        )
    );

endmodule