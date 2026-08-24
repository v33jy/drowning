`timescale 1ns / 1ps

/*
 * Raspberry Pi SPI0(MODE0)에서 RTL-SDR unsigned 8-bit I/Q 스트림을 수신합니다.
 *
 * 전송 패킷:
 *   0..3   : ASCII "IQF1"
 *   4..7   : sequence, little-endian uint32
 *   8..11  : sample_count, little-endian uint32 (1..4096, 1024의 배수)
 *   12..13 : target_bin, little-endian uint16 (0..1023)
 *   14     : detect_shift (0..15)
 *   15     : flags[0] = 1이면 전체 스펙트럼 최대 피크 탐지,
 *                     0이면 target_bin 주변 대역 탐지
 *   16..   : I0,Q0,I1,Q1,... (각각 unsigned 8-bit)
 *
 * SPI 신호는 100 MHz 시스템 클럭으로 동기화/오버샘플링합니다.
 * Raspberry Pi SPI 속도는 20 MHz 이하로 사용하십시오.
 */
module spi_iq_source #(
    parameter integer FIFO_DEPTH = 8192
)(
    input  wire                    clk,
    input  wire                    reset,

    input  wire                    spi_sclk,
    input  wire                    spi_mosi,
    input  wire                    spi_cs_n,

    input  wire                    sample_ready,
    output wire signed [15:0]      sample_i,
    output wire signed [15:0]      sample_q,
    output wire                    sample_valid,
    output wire                    sample_last,

    output reg  [9:0]              target_bin_cfg,
    output reg  [3:0]              detect_shift_cfg,
    output reg                     detect_any_peak_cfg,

    output reg                     packet_seen,
    output reg                     overflow_latched,
    output reg                     protocol_error_latched
);

    localparam [1:0] STATE_HEADER  = 2'd0;
    localparam [1:0] STATE_PAYLOAD = 2'd1;
    localparam [1:0] STATE_DROP    = 2'd2;

    // -----------------------------------------------------
    // 비동기 SPI 입력 동기화
    // -----------------------------------------------------
    (* ASYNC_REG = "TRUE" *) reg [2:0] sclk_sync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] mosi_sync;
    (* ASYNC_REG = "TRUE" *) reg [2:0] cs_sync;

    always @(posedge clk) begin
        if (reset) begin
            sclk_sync <= 3'b000;
            mosi_sync <= 3'b000;
            cs_sync   <= 3'b111;
        end
        else begin
            sclk_sync <= {sclk_sync[1:0], spi_sclk};
            mosi_sync <= {mosi_sync[1:0], spi_mosi};
            cs_sync   <= {cs_sync[1:0], spi_cs_n};
        end
    end

    wire sclk_rise;
    wire cs_active;
    wire cs_rise;

    assign sclk_rise = (sclk_sync[2:1] == 2'b01);
    assign cs_active = ~cs_sync[2];
    assign cs_rise   = (cs_sync[2:1] == 2'b01);

    // -----------------------------------------------------
    // SPI 바이트 수신 및 패킷 파서
    // -----------------------------------------------------
    reg [7:0] shift_reg;
    reg [2:0] bit_count;
    reg [1:0] parser_state;
    reg [4:0] header_index;
    reg       magic_ok;

    reg [31:0] sequence_reg;
    reg [31:0] sample_count_reg;
    reg [15:0] target_bin_reg;
    reg [7:0]  detect_shift_reg;

    reg [31:0] samples_remaining;
    reg [9:0]  sample_in_fft_frame;
    reg        iq_phase;
    reg [7:0]  i_byte;

    wire [7:0] received_byte;
    assign received_byte = {shift_reg[6:0], mosi_sync[2]};

    // FIFO 입력: {TLAST, I[7:0], Q[7:0]}
    reg [16:0] fifo_din;
    reg        fifo_wr_en;
    wire       fifo_full;
    wire       fifo_prog_full;
    wire       fifo_overflow;
    wire       fifo_wr_rst_busy;

    always @(posedge clk) begin
        fifo_wr_en <= 1'b0;

        if (reset) begin
            shift_reg              <= 8'd0;
            bit_count              <= 3'd0;
            parser_state           <= STATE_HEADER;
            header_index           <= 5'd0;
            magic_ok               <= 1'b1;
            sequence_reg           <= 32'd0;
            sample_count_reg       <= 32'd0;
            target_bin_reg         <= 16'd256;
            detect_shift_reg       <= 8'd5;
            samples_remaining      <= 32'd0;
            sample_in_fft_frame    <= 10'd0;
            iq_phase               <= 1'b0;
            i_byte                 <= 8'd0;
            fifo_din               <= 17'd0;

            target_bin_cfg         <= 10'd256;
            detect_shift_cfg       <= 4'd5;
            detect_any_peak_cfg    <= 1'b1;
            packet_seen            <= 1'b0;
            overflow_latched       <= 1'b0;
            protocol_error_latched <= 1'b0;
        end
        else begin
            if (fifo_overflow) begin
                overflow_latched <= 1'b1;
            end

            // CS가 비활성화되면 다음 패킷 헤더를 기다립니다.
            if (cs_rise || !cs_active) begin
                bit_count    <= 3'd0;
                parser_state <= STATE_HEADER;
                header_index <= 5'd0;
                magic_ok     <= 1'b1;
                iq_phase     <= 1'b0;
            end
            else if (sclk_rise) begin
                shift_reg <= received_byte;

                if (bit_count == 3'd7) begin
                    bit_count <= 3'd0;

                    case (parser_state)
                        STATE_HEADER: begin
                            case (header_index)
                                5'd0: begin
                                    if (received_byte != 8'h49) magic_ok <= 1'b0; // I
                                end
                                5'd1: begin
                                    if (received_byte != 8'h51) magic_ok <= 1'b0; // Q
                                end
                                5'd2: begin
                                    if (received_byte != 8'h46) magic_ok <= 1'b0; // F
                                end
                                5'd3: begin
                                    if (received_byte != 8'h31) magic_ok <= 1'b0; // 1
                                end
                                5'd4: sequence_reg[7:0]   <= received_byte;
                                5'd5: sequence_reg[15:8]  <= received_byte;
                                5'd6: sequence_reg[23:16] <= received_byte;
                                5'd7: sequence_reg[31:24] <= received_byte;
                                5'd8: sample_count_reg[7:0]   <= received_byte;
                                5'd9: sample_count_reg[15:8]  <= received_byte;
                                5'd10: sample_count_reg[23:16] <= received_byte;
                                5'd11: sample_count_reg[31:24] <= received_byte;
                                5'd12: target_bin_reg[7:0]  <= received_byte;
                                5'd13: target_bin_reg[15:8] <= received_byte;
                                5'd14: detect_shift_reg     <= received_byte;
                                5'd15: begin
                                    if (
                                        magic_ok &&
                                        (sample_count_reg >= 32'd1024) &&
                                        (sample_count_reg <= 32'd4096) &&
                                        (sample_count_reg[9:0] == 10'd0) &&
                                        (target_bin_reg < 16'd1024) &&
                                        (detect_shift_reg < 8'd16)
                                    ) begin
                                        samples_remaining   <= sample_count_reg;
                                        sample_in_fft_frame <= 10'd0;
                                        iq_phase            <= 1'b0;
                                        target_bin_cfg      <= target_bin_reg[9:0];
                                        detect_shift_cfg    <= detect_shift_reg[3:0];
                                        detect_any_peak_cfg <= received_byte[0];
                                        packet_seen         <= 1'b1;
                                        parser_state        <= STATE_PAYLOAD;
                                    end
                                    else begin
                                        protocol_error_latched <= 1'b1;
                                        parser_state           <= STATE_DROP;
                                    end
                                end
                                default: parser_state <= STATE_DROP;
                            endcase

                            if (header_index != 5'd15) begin
                                header_index <= header_index + 1'b1;
                            end
                        end

                        STATE_PAYLOAD: begin
                            if (!iq_phase) begin
                                i_byte   <= received_byte;
                                iq_phase <= 1'b1;
                            end
                            else begin
                                iq_phase <= 1'b0;

                                if (!fifo_full && !fifo_wr_rst_busy) begin
                                    fifo_din <= {
                                        (sample_in_fft_frame == 10'd1023),
                                        i_byte,
                                        received_byte
                                    };
                                    fifo_wr_en <= 1'b1;
                                end
                                else begin
                                    overflow_latched <= 1'b1;
                                end

                                if (sample_in_fft_frame == 10'd1023) begin
                                    sample_in_fft_frame <= 10'd0;
                                end
                                else begin
                                    sample_in_fft_frame <= sample_in_fft_frame + 1'b1;
                                end

                                if (samples_remaining == 32'd1) begin
                                    samples_remaining <= 32'd0;
                                    parser_state      <= STATE_DROP;
                                end
                                else begin
                                    samples_remaining <= samples_remaining - 1'b1;
                                end
                            end
                        end

                        default: begin
                            // 현재 CS 구간의 남은 바이트는 무시합니다.
                        end
                    endcase
                end
                else begin
                    bit_count <= bit_count + 1'b1;
                end
            end
        end
    end

    // -----------------------------------------------------
    // 시스템 클럭 도메인의 동기 FIFO
    // -----------------------------------------------------
    wire [16:0] fifo_dout;
    wire        fifo_empty;
    wire        fifo_underflow;
    wire        fifo_rd_rst_busy;
    wire        fifo_rd_en;

    wire almost_empty_unused;
    wire almost_full_unused;
    wire data_valid_unused;
    wire dbiterr_unused;
    wire prog_empty_unused;
    wire sbiterr_unused;
    wire wr_ack_unused;
    wire [13:0] rd_data_count_unused;
    wire [13:0] wr_data_count_unused;

    assign fifo_rd_en = sample_valid && sample_ready;
    assign sample_valid = !fifo_empty && !fifo_rd_rst_busy;
    assign sample_last  = fifo_dout[16];

    wire signed [8:0] i_centered;
    wire signed [8:0] q_centered;
    wire signed [15:0] i_extended;
    wire signed [15:0] q_extended;

    assign i_centered = $signed({1'b0, fifo_dout[15:8]}) - 9'sd128;
    assign q_centered = $signed({1'b0, fifo_dout[7:0]})  - 9'sd128;
    assign i_extended = {{7{i_centered[8]}}, i_centered};
    assign q_extended = {{7{q_centered[8]}}, q_centered};

    // 8-bit RTL-SDR 샘플을 16-bit FFT 입력 범위로 확대합니다.
    assign sample_i = i_extended <<< 7;
    assign sample_q = q_extended <<< 7;

    xpm_fifo_sync #(
        .DOUT_RESET_VALUE    ("0"),
        .ECC_MODE            ("no_ecc"),
        .FIFO_MEMORY_TYPE    ("block"),
        .FIFO_READ_LATENCY   (0),
        .FIFO_WRITE_DEPTH    (FIFO_DEPTH),
        .FULL_RESET_VALUE    (0),
        .PROG_EMPTY_THRESH   (10),
        .PROG_FULL_THRESH    (FIFO_DEPTH - 256),
        .RD_DATA_COUNT_WIDTH (14),
        .READ_DATA_WIDTH     (17),
        .READ_MODE           ("fwft"),
        .SIM_ASSERT_CHK      (0),
        .USE_ADV_FEATURES    ("0707"),
        .WAKEUP_TIME         (0),
        .WR_DATA_COUNT_WIDTH (14),
        .WRITE_DATA_WIDTH    (17)
    ) u_iq_fifo (
        .almost_empty  (almost_empty_unused),
        .almost_full   (almost_full_unused),
        .data_valid    (data_valid_unused),
        .dbiterr       (dbiterr_unused),
        .dout          (fifo_dout),
        .empty         (fifo_empty),
        .full          (fifo_full),
        .overflow      (fifo_overflow),
        .prog_empty    (prog_empty_unused),
        .prog_full     (fifo_prog_full),
        .rd_data_count (rd_data_count_unused),
        .rd_rst_busy   (fifo_rd_rst_busy),
        .sbiterr       (sbiterr_unused),
        .underflow     (fifo_underflow),
        .wr_ack        (wr_ack_unused),
        .wr_data_count (wr_data_count_unused),
        .wr_rst_busy   (fifo_wr_rst_busy),
        .din           (fifo_din),
        .injectdbiterr (1'b0),
        .injectsbiterr (1'b0),
        .rd_en         (fifo_rd_en),
        .rst           (reset),
        .sleep         (1'b0),
        .wr_clk        (clk),
        .wr_en         (fifo_wr_en)
    );

endmodule
