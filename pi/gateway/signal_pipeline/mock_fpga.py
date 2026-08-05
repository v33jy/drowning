import cmath
import math

from signal_pipeline.fpga_protocol import decode_iq_packet
from signal_pipeline.models import FpgaResult


class MockFpgaTransport:
    """
    실제 Basys 3 FPGA(1024-point FFT)를 흉내 내서, Raspberry Pi 안에서
    순수 DFT로 같은 스펙트럼 결과를 계산한다. DFT와 FFT는 결과가 동일하고
    계산 속도만 다르다 — 성능 관련 설명은 _dft() 참고.

    입력은 FPGA에 보낼 것과 동일한 bytes 패킷이고,
    출력은 실제 FPGA가 나중에 반환해야 할 FpgaResult 형식이다.
    """

    def __init__(
        self,
        detection_threshold_dbm: float = -45.0,
        reference_amplitude: float = 32768.0,
        sample_rate_hz: int = 2_400_000,
        center_frequency_hz: int = 915_000_000,
    ) -> None:
        self.detection_threshold_dbm = detection_threshold_dbm
        self.reference_amplitude = reference_amplitude
        self.sample_rate_hz = sample_rate_hz
        self.center_frequency_hz = center_frequency_hz

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

        peak_bin = max(
            range(len(powers)),
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
            rss_dbm=rss_dbm,
            detected=rss_dbm >= self.detection_threshold_dbm,
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