from config import settings
from signal_pipeline.fpga_protocol import FFT_SIZE
from signal_pipeline.mock_fpga import MockFpgaTransport
from signal_pipeline.mock_sdr import MockSdrSource
from signal_pipeline.rtl_sdr import RtlSdrSource
from signal_pipeline.spi_fpga import SpiFpgaTransport


_TARGET_BIN = 128


def _sdr_gain() -> str | float:
    if settings.sdr_gain.lower() == "auto":
        return "auto"

    try:
        return float(settings.sdr_gain)
    except ValueError as error:
        raise ValueError("SDR_GAIN must be 'auto' or a number") from error


def create_sdr_source() -> MockSdrSource | RtlSdrSource:
    mode = settings.sdr_mode.lower()

    if mode == "mock":
        print("[SDR] using MockSdrSource")
        return MockSdrSource(
            fft_size=FFT_SIZE,
            tone_bin=_TARGET_BIN,
            amplitude=12_000,
            noise_amplitude=500,
        )

    if mode == "real":
        print("[SDR] using RtlSdrSource")
        return RtlSdrSource(
            sample_rate_hz=settings.sdr_sample_rate_hz,
            center_frequency_hz=settings.sdr_center_frequency_hz,
            fft_size=FFT_SIZE,
            gain=_sdr_gain(),
        )

    raise ValueError(f"Unsupported SDR_MODE: {settings.sdr_mode}")


def create_fpga_transport() -> MockFpgaTransport | SpiFpgaTransport:
    mode = settings.fpga_mode.lower()

    if mode == "mock":
        print("[FPGA] using MockFpgaTransport")
        return MockFpgaTransport()

    if mode == "real":
        print("[FPGA] using SpiFpgaTransport")
        return SpiFpgaTransport(
            bus=settings.spi_bus,
            device=settings.spi_device,
            max_speed_hz=settings.spi_max_speed_hz,
            mode=settings.spi_mode,
        )

    raise ValueError(f"Unsupported FPGA_MODE: {settings.fpga_mode}")
