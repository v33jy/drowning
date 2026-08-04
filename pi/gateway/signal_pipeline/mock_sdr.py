import math
import random

from signal_pipeline.models import IQFrame


class MockSdrSource:
    """
    실제 RTL-SDR 대신 16개의 가상 I/Q 샘플을 생성한다.

    FPGA의 16-point FFT 입력을 흉내 내기 위해
    한 프레임마다 정확히 16개의 샘플을 반환한다.
    """

    def __init__(
        self,
        sample_rate_hz: int = 2_400_000,
        center_frequency_hz: int = 915_000_000,
        fft_size: int = 16,
        tone_bin: int = 3,
        amplitude: int = 12_000,
        noise_amplitude: int = 500,
    ) -> None:
        if fft_size != 16:
            raise ValueError("This project currently uses a 16-point FFT")

        if not 0 <= tone_bin < fft_size:
            raise ValueError("tone_bin must be between 0 and fft_size - 1")

        if amplitude <= 0:
            raise ValueError("amplitude must be greater than zero")

        if noise_amplitude < 0:
            raise ValueError("noise_amplitude must be zero or greater")

        self.sample_rate_hz = sample_rate_hz
        self.center_frequency_hz = center_frequency_hz
        self.fft_size = fft_size
        self.tone_bin = tone_bin
        self.amplitude = amplitude
        self.noise_amplitude = noise_amplitude
        self._sequence = 0

    def next_frame(self) -> IQFrame:
        """
        16개의 가상 복소수 신호를 생성하여 IQFrame으로 반환한다.
        """

        samples: list[tuple[int, int]] = []

        for sample_index in range(self.fft_size):
            angle = (
                2.0
                * math.pi
                * self.tone_bin
                * sample_index
                / self.fft_size
            )

            i_noise = random.randint(
                -self.noise_amplitude,
                self.noise_amplitude,
            )
            q_noise = random.randint(
                -self.noise_amplitude,
                self.noise_amplitude,
            )

            i_value = round(self.amplitude * math.cos(angle)) + i_noise
            q_value = round(self.amplitude * math.sin(angle)) + q_noise

            i_value = max(-32768, min(32767, i_value))
            q_value = max(-32768, min(32767, q_value))

            samples.append((i_value, q_value))

        frame = IQFrame(
            sequence=self._sequence,
            sample_rate_hz=self.sample_rate_hz,
            center_frequency_hz=self.center_frequency_hz,
            samples=samples,
        )

        self._sequence += 1
        return frame