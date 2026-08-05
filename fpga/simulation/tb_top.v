`timescale 1ns / 1ps

module tb_top;

    reg CLK100MHZ = 1'b0;
    reg BTNC      = 1'b0;

    reg SW0 = 1'b1;
    reg SW1 = 1'b0;
    reg SW2 = 1'b0;

    wire LD0;
    wire LD1;
    wire LD2;

    integer pass_count = 0;


    // 100 MHz clock
    always #5 CLK100MHZ =
        ~CLK100MHZ;


    top dut (
        .CLK100MHZ (CLK100MHZ),
        .BTNC      (BTNC),

        .SW0       (SW0),
        .SW1       (SW1),
        .SW2       (SW2),

        .LD0       (LD0),
        .LD1       (LD1),
        .LD2       (LD2)
    );


    task run_scenario;

        input [1:0] scenario_id;
        input       expected_detected;
        input       check_peak_128;

        integer timeout_count;

        begin
            // 시험 시나리오 선택
            {SW2, SW1} = scenario_id;

            repeat (20)
                @(posedge CLK100MHZ);

            // BTNC 버튼 입력 모사
            BTNC = 1'b1;

            repeat (10)
                @(posedge CLK100MHZ);

            BTNC = 1'b0;

            $display("----------------------------------------");
            $display(
                "Scenario %02b started",
                scenario_id
            );

            timeout_count = 0;

            // FFT 결과 완료를 기다립니다.
            while (
                dut.result_done !== 1'b1
                &&
                timeout_count < 300000
            ) begin
                @(posedge CLK100MHZ);

                timeout_count =
                    timeout_count + 1;
            end

            if (timeout_count >= 300000) begin
                $display(
                    "FAIL: Scenario %02b timeout",
                    scenario_id
                );

                $finish;
            end

            $display(
                "detected     = %0d",
                dut.detected
            );

            $display(
                "peak_bin     = %0d",
                dut.peak_bin
            );

            $display(
                "target_power = %0d",
                dut.target_power
            );

            $display(
                "noise_floor  = %0d",
                dut.noise_floor
            );

            $display(
                "FFT error    = %0d",
                dut.error_latched
            );

            if (
                dut.detected
                !==
                expected_detected
            ) begin
                $display(
                    "FAIL: Scenario %02b detection mismatch",
                    scenario_id
                );
            end

            else if (
                dut.error_latched
                !==
                1'b0
            ) begin
                $display(
                    "FAIL: Scenario %02b FFT interface error",
                    scenario_id
                );
            end

            else if (
                check_peak_128
                &&
                (
                    dut.peak_bin < 10'd126
                    ||
                    dut.peak_bin > 10'd130
                )
            ) begin
                $display(
                    "FAIL: Scenario %02b peak bin mismatch",
                    scenario_id
                );
            end

            else begin
                $display(
                    "PASS: Scenario %02b",
                    scenario_id
                );

                pass_count =
                    pass_count + 1;
            end

            // 다음 시험 전 대기
            repeat (50)
                @(posedge CLK100MHZ);
        end

    endtask


    initial begin

        $display("========================================");
        $display("Multi-scenario FPGA signal test");
        $display("========================================");

        SW0 = 1'b1;
        BTNC = 1'b0;
        SW1 = 1'b0;
        SW2 = 1'b0;

        repeat (20)
            @(posedge CLK100MHZ);

        SW0 = 1'b0;

        // FFT IP 설정 완료 대기
        wait (
            dut.config_done === 1'b1
        );

        $display(
            "FFT configuration complete"
        );

        // 00: 목표 없음 → DET=0
        run_scenario(
            2'b00,
            1'b0,
            1'b0
        );

        // 01: 강한 목표 → DET=1, peak bin 128 부근
        run_scenario(
            2'b01,
            1'b1,
            1'b1
        );

        // 10: 약한 목표 + 강한 잡음 → DET=1
        run_scenario(
            2'b10,
            1'b1,
            1'b0
        );

        // 11: 목표 없이 강한 타 주파수 간섭 → DET=0
        run_scenario(
            2'b11,
            1'b0,
            1'b0
        );

        $display("========================================");

        $display(
            "Passed scenarios: %0d / 4",
            pass_count
        );

        if (pass_count == 4) begin
            $display(
                "ALL SCENARIOS PASS"
            );
        end

        else begin
            $display(
                "SOME SCENARIOS FAILED"
            );
        end

        $display("========================================");

        repeat (20)
            @(posedge CLK100MHZ);

        $finish;
    end

endmodule