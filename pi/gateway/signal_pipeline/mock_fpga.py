import cmath
import math

from signal_pipeline.fpga_protocol import decode_iq_packet
from signal_pipeline.models import FpgaResult


# fpga/rtl/spectrum_analyzer.v와 동일한 기본값 — 탐지 판정 자체를 그 RTL과
# 똑같은 알고리즘으로 흉내 내기 위해 숫자까지 그대로 맞춘 것.
_TARGET_BIN = 128
_INTERFERENCE_BIN = 310
_BAND_HALF_WIDTH = 2
_DETECT_SHIFT = 5


class MockFpgaTransport:
    """
    실제 Basys 3 FPGA(1024-point FFT)를 흉내 내서, Raspberry Pi 안에서
    순수 DFT로 같은 스펙트럼 결과를 계산한다. DFT와 FFT는 결과가 동일하고
    계산 속도만 다르다 — 성능 관련 설명은 _dft() 참고.

    탐지 판정은 절대 dBm 임계값이 아니라 fpga/rtl/spectrum_analyzer.v와 같은
    방식 — 고정된 target_bin 주변 대역 전력 합이, interference_bin 등을 제외한
    나머지 bin들로 추정한 잡음 바닥의 2**detect_shift배를 넘는지로 판단한다.
    (전에는 mock이 "peak bin + 절대 dBm 임계값"이라는 다른 기준을 썼는데,
    실제 하드웨어가 오면 그 기준으로 검증한 게 아무 의미가 없어서 통일함.)

    입력은 FPGA에 보낼 것과 동일한 bytes 패킷이고,
    출력은 실제 FPGA가 나중에 반환해야 할 FpgaResult 형식이다.
    """

    def __init__(
        self,
        reference_amplitude: float = 32768.0,
        sample_rate_hz: int = 2_400_000,
        center_frequency_hz: int = 915_000_000,
        target_bin: int = _TARGET_BIN,
        interference_bin: int = _INTERFERENCE_BIN,
        band_half_width: int = _BAND_HALF_WIDTH,
        detect_shift: int = _DETECT_SHIFT,
    ) -> None:
        self.reference_amplitude = reference_amplitude
        self.sample_rate_hz = sample_rate_hz
        self.center_frequency_hz = center_frequency_hz
        self.target_bin = target_bin
        self.interference_bin = interference_bin
        self.band_half_width = band_half_width
        self.detect_shift = detect_shift

    def process(self, packet: bytes) -> FpgaResult:
        """
        FPGA 전송용 바이트 패킷을 받아 DFT와 RSSI 계산을 수행한다.
        """

        frame = decode_iq_packet(
            packet,
            sample_rate_hz=self.sample_rate_hz,
            center_frequency_hz=self.center_frequency_hz,
        )
        complex_samples = [
            complex(i_value, q_value)
            for i_value, q_value in frame.samples
        ]

        spectrum = self._dft(complex_samples)
        powers = [abs(value) ** 2 for value in spectrum]
        fft_size = len(powers)

        target_low = self.target_bin - self.band_half_width
        target_high = self.target_bin + self.band_half_width
        interference_low = self.interference_bin - self.band_half_width
        interference_high = self.interference_bin + self.band_half_width

        target_power = sum(
            powers[bin_index]
            for bin_index in range(target_low, target_high + 1)
        )

        noise_sum = sum(
            power
            for bin_index, power in enumerate(powers)
            if bin_index != 0
            and not target_low <= bin_index <= target_high
            and not interference_low <= bin_index <= interference_high
        )

        # RTL도 실제 잡음 bin 개수가 아니라 항상 fft_size(1024)로 나눠서
        # 근사한다(spectrum_analyzer.v 주석 참고) — 그대로 따라감.
        noise_floor = noise_sum / fft_size

        detected = target_power > noise_floor * (2 ** self.detect_shift)

        # bin 0(DC)은 RTL도 피크 후보에서 제외함
        peak_bin = max(
            range(1, fft_size),
            key=powers.__getitem__,
        )
        peak_power = powers[peak_bin]

        rms_amplitude = math.sqrt(
            sum(abs(sample) ** 2 for sample in complex_samples)
            / len(complex_samples)
        )

        normalized_amplitude = max(
            rms_amplitude / self.reference_amplitude,
            1e-12,
        )

        rss_dbm = 20.0 * math.log10(normalized_amplitude)

        return FpgaResult(
            sequence=frame.sequence,
            peak_bin=peak_bin,
            peak_power=peak_power,
            target_power=target_power,
            noise_floor=noise_floor,
            rss_dbm=rss_dbm,
            detected=detected,
        )

    @staticmethod
    def _dft(samples: list[complex]) -> list[complex]:
        """
        1024-point DFT를 계산한다.

        실제 FPGA에서는 병렬 FFT 회로가 이 역할을 수행한다.
        Mock에서는 Python으로 같은 결과를 계산한다.

        O(N^2)라 1024포인트 기준 프레임당 수백 ms 걸림 — 지금 SEND_INTERVAL(기본
        2초) 대비로는 여유 있지만, 이 mock을 그보다 훨씬 짧은 주기로 돌릴 일이
        생기면 (실제 FPGA 대신 계속 이 경로를 쓸 경우) radix-2 FFT로 바꿔야 함.
        """

        sample_count = len(samples)
        spectrum: list[complex] = []

        for frequency_bin in range(sample_count):
            bin_value = 0j

            for sample_index, sample in enumerate(samples):
                angle = (
                    -2.0
                    * math.pi
                    * frequency_bin
                    * sample_index
                    / sample_count
                )

                bin_value += sample * cmath.exp(1j * angle)

            spectrum.append(bin_value)

        return spectrum
