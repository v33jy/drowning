import cmath
import math

from signal_pipeline.fpga_protocol import decode_iq_packet
from signal_pipeline.models import FpgaResult


class MockFpgaTransport:
    """
    실제 Basys 3 FPGA 대신 Raspberry Pi 안에서 16-point FFT를 수행한다.

    입력은 FPGA에 보낼 것과 동일한 bytes 패킷이고,
    출력은 실제 FPGA가 나중에 반환해야 할 FpgaResult 형식이다.
    """

    def __init__(
        self,
        detection_threshold_dbm: float = -45.0,
        reference_amplitude: float = 32768.0,
    ) -> None:
        self.detection_threshold_dbm = detection_threshold_dbm
        self.reference_amplitude = reference_amplitude

    def process(self, packet: bytes) -> FpgaResult:
        """
        FPGA 전송용 바이트 패킷을 받아 FFT와 RSSI 계산을 수행한다.
        """

        frame = decode_iq_packet(packet)
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
        16-point DFT를 계산한다.

        실제 FPGA에서는 병렬 FFT 회로가 이 역할을 수행한다.
        Mock에서는 Python으로 같은 결과를 계산한다.
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