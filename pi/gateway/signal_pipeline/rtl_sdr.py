from signal_pipeline.fpga_protocol import FFT_SIZE
from signal_pipeline.models import IQFrame


class RtlSdrSource:
    """Read normalized RTL-SDR samples as signed 16-bit IQ frames."""

    def __init__(
        self,
        sample_rate_hz: int = 2_400_000,
        center_frequency_hz: int = 915_000_000,
        fft_size: int = FFT_SIZE,
        gain: str | float = "auto",
    ) -> None:
        if fft_size != FFT_SIZE:
            raise ValueError(f"fft_size must be {FFT_SIZE}")
        if sample_rate_hz <= 0:
            raise ValueError("sample_rate_hz must be greater than zero")
        if center_frequency_hz <= 0:
            raise ValueError("center_frequency_hz must be greater than zero")

        self.sample_rate_hz = sample_rate_hz
        self.center_frequency_hz = center_frequency_hz
        self.fft_size = fft_size
        self.gain = gain
        self._sequence = 0
        self._sdr = None

    def open(self) -> None:
        if self._sdr is not None:
            return

        try:
            from rtlsdr import RtlSdr
        except ImportError as error:
            raise RuntimeError(
                "pyrtlsdr is not installed. Install hardware requirements first."
            ) from error

        try:
            sdr = RtlSdr()
            sdr.sample_rate = self.sample_rate_hz
            sdr.center_freq = self.center_frequency_hz
            sdr.gain = self.gain
        except Exception as error:
            raise RuntimeError(f"Failed to open RTL-SDR device: {error}") from error

        self._sdr = sdr

    def next_frame(self) -> IQFrame:
        if self._sdr is None:
            self.open()

        raw_samples = self._sdr.read_samples(self.fft_size)
        if len(raw_samples) != self.fft_size:
            raise RuntimeError(
                f"Expected {self.fft_size} RTL-SDR samples, got {len(raw_samples)}"
            )

        samples = [
            (
                max(-32768, min(32767, int(round(sample.real * 32767)))),
                max(-32768, min(32767, int(round(sample.imag * 32767)))),
            )
            for sample in raw_samples
        ]
        frame = IQFrame(
            sequence=self._sequence,
            sample_rate_hz=self.sample_rate_hz,
            center_frequency_hz=self.center_frequency_hz,
            samples=samples,
        )
        self._sequence += 1
        return frame

    def close(self) -> None:
        if self._sdr is None:
            return

        sdr, self._sdr = self._sdr, None
        try:
            sdr.close()
        except Exception as error:
            raise RuntimeError(f"Failed to close RTL-SDR device: {error}") from error
