from pathlib import Path

import numpy as np


FFT_LENGTH = 1024

TARGET_BIN = 128
KNOWN_INTERFERENCE_BIN = 310

# Python 파일과 같은 폴더에 .mem 파일을 생성합니다.
OUTPUT_DIRECTORY = Path(__file__).resolve().parent


def to_unsigned_16(value: int) -> int:
    return value & 0xFFFF


def create_signal(
    scenario: int,
    target_amplitude: float,
    interference_amplitude: float,
    interference_bin: int,
    noise_sigma: float,
    chirp_amplitude: float,
) -> None:
    rng = np.random.default_rng(
        seed=20260804 + scenario
    )

    n = np.arange(
        FFT_LENGTH,
        dtype=np.float64,
    )

    # 시간에 따라 목표 신호 세기가 변하는 fading
    fading = (
        0.75
        + 0.25
        * np.sin(
            2.0
            * np.pi
            * 3.0
            * n
            / FFT_LENGTH
        )
    )

    # 목표 신호: bin 128
    target = (
        target_amplitude
        * fading
        * np.exp(
            1j
            * 2.0
            * np.pi
            * TARGET_BIN
            * n
            / FFT_LENGTH
        )
    )

    # 다른 주파수의 간섭 신호
    interference = (
        interference_amplitude
        * np.exp(
            1j
            * 2.0
            * np.pi
            * interference_bin
            * n
            / FFT_LENGTH
        )
    )

    # 주파수가 bin 40에서 220 방향으로 변하는 chirp 간섭
    chirp_start_bin = 40.0
    chirp_end_bin = 220.0

    chirp_phase = (
        2.0
        * np.pi
        * (
            chirp_start_bin
            * n
            / FFT_LENGTH
            + 0.5
            * (
                chirp_end_bin
                - chirp_start_bin
            )
            * (n / FFT_LENGTH) ** 2
        )
    )

    chirp = (
        chirp_amplitude
        * np.exp(1j * chirp_phase)
    )

    # 복소 백색 잡음
    noise = (
        noise_sigma
        / np.sqrt(2.0)
        * (
            rng.standard_normal(FFT_LENGTH)
            + 1j
            * rng.standard_normal(FFT_LENGTH)
        )
    )

    # 실제 수신기에서 발생할 수 있는 DC 오프셋 모사
    dc_offset = 0.05 + 0.03j

    samples = (
        target
        + interference
        + chirp
        + noise
        + dc_offset
    )

    # I와 Q 모두 16비트 범위에 들어오도록 조정
    maximum = max(
        float(np.max(np.abs(samples.real))),
        float(np.max(np.abs(samples.imag))),
        1e-12,
    )

    if maximum > 0.95:
        samples = samples * (0.95 / maximum)

    i_values = np.clip(
        np.round(samples.real * 32767.0),
        -32768,
        32767,
    ).astype(np.int16)

    q_values = np.clip(
        np.round(samples.imag * 32767.0),
        -32768,
        32767,
    ).astype(np.int16)

    output_file = (
        OUTPUT_DIRECTORY
        / f"iq_test_{scenario}.mem"
    )

    # 한 줄의 구조:
    # 상위 16비트 = Q
    # 하위 16비트 = I
    with output_file.open(
        "w",
        encoding="ascii",
    ) as file:
        for i_value, q_value in zip(
            i_values,
            q_values,
        ):
            i_unsigned = to_unsigned_16(
                int(i_value)
            )

            q_unsigned = to_unsigned_16(
                int(q_value)
            )

            packed_value = (
                (q_unsigned << 16)
                | i_unsigned
            )

            file.write(
                f"{packed_value:08X}\n"
            )

    # Python FFT로 생성 데이터의 예상 결과 확인
    spectrum = np.fft.fft(samples)
    power = np.abs(spectrum) ** 2

    target_power = float(
        np.sum(power[126:131])
    )

    noise_mask = np.ones(
        FFT_LENGTH,
        dtype=bool,
    )

    noise_mask[0] = False
    noise_mask[126:131] = False
    noise_mask[308:313] = False

    noise_floor = float(
        np.sum(power[noise_mask])
        / 1024.0
    )

    expected_detected = (
        target_power
        >
        noise_floor * 32.0
    )

    peak_power = power.copy()
    peak_power[0] = 0.0

    peak_bin = int(
        np.argmax(peak_power)
    )

    print("--------------------------------")
    print(f"시나리오: {scenario:02b}")
    print(f"저장 파일: {output_file}")
    print(f"peak bin: {peak_bin}")

    print(
        "target/noise 비율:",
        round(
            target_power
            / max(noise_floor, 1e-12),
            2,
        ),
    )

    print(
        "예상 DET:",
        int(expected_detected),
    )


def main() -> None:
    # 00: 목표 없음, 일반 잡음과 bin 310 간섭
    create_signal(
        scenario=0,
        target_amplitude=0.00,
        interference_amplitude=0.28,
        interference_bin=310,
        noise_sigma=0.12,
        chirp_amplitude=0.12,
    )

    # 01: 강한 목표 신호
    create_signal(
        scenario=1,
        target_amplitude=0.55,
        interference_amplitude=0.28,
        interference_bin=310,
        noise_sigma=0.12,
        chirp_amplitude=0.12,
    )

    # 10: 약한 목표 신호와 강한 잡음
    create_signal(
        scenario=2,
        target_amplitude=0.18,
        interference_amplitude=0.28,
        interference_bin=310,
        noise_sigma=0.16,
        chirp_amplitude=0.12,
    )

    # 11: 목표 없음, bin 400의 강한 간섭
    create_signal(
        scenario=3,
        target_amplitude=0.00,
        interference_amplitude=0.75,
        interference_bin=400,
        noise_sigma=0.12,
        chirp_amplitude=0.12,
    )

    print()
    print("4개 시험 데이터 생성 완료")


if __name__ == "__main__":
    main()