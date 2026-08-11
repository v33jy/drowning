from signal_pipeline.fpga_protocol import PACKET_SIZE
from signal_pipeline.fpga_result_protocol import (
    RESULT_PACKET_SIZE,
    decode_fpga_result,
)
from signal_pipeline.models import FpgaResult


class SpiFpgaTransport:
    """Exchange IQ and result packets with an FPGA over Raspberry Pi SPI."""

    def __init__(
        self,
        bus: int = 0,
        device: int = 0,
        max_speed_hz: int = 1_000_000,
        mode: int = 0,
    ) -> None:
        if bus < 0 or device < 0:
            raise ValueError("SPI bus and device must be zero or greater")
        if max_speed_hz <= 0:
            raise ValueError("SPI speed must be greater than zero")
        if mode not in (0, 1, 2, 3):
            raise ValueError("SPI mode must be 0, 1, 2, or 3")

        self.bus = bus
        self.device = device
        self.max_speed_hz = max_speed_hz
        self.mode = mode
        self._spi = None

    def open(self) -> None:
        if self._spi is not None:
            return

        try:
            import spidev
        except ImportError as error:
            raise RuntimeError(
                "spidev is not installed. Install hardware requirements first."
            ) from error

        try:
            spi = spidev.SpiDev()
            spi.open(self.bus, self.device)
            spi.max_speed_hz = self.max_speed_hz
            spi.mode = self.mode
        except Exception as error:
            raise RuntimeError(f"Failed to open SPI device: {error}") from error

        self._spi = spi

    def process(self, packet: bytes) -> FpgaResult:
        if len(packet) != PACKET_SIZE:
            raise ValueError(
                f"Expected FPGA input packet size {PACKET_SIZE}, got {len(packet)}"
            )
        if self._spi is None:
            self.open()

        try:
            self._spi.xfer2(list(packet))
            raw_result = self._spi.xfer2([0] * RESULT_PACKET_SIZE)
        except Exception as error:
            raise RuntimeError(f"FPGA SPI processing failed: {error}") from error

        return decode_fpga_result(bytes(raw_result))

    def close(self) -> None:
        if self._spi is None:
            return

        spi, self._spi = self._spi, None
        try:
            spi.close()
        except Exception as error:
            raise RuntimeError(f"Failed to close SPI device: {error}") from error
