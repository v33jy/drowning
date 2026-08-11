import unittest
from unittest.mock import patch

from config import settings
from signal_pipeline.factory import create_fpga_transport, create_sdr_source
from signal_pipeline.mock_fpga import MockFpgaTransport
from signal_pipeline.mock_sdr import MockSdrSource
from signal_pipeline.rtl_sdr import RtlSdrSource
from signal_pipeline.spi_fpga import SpiFpgaTransport


class FactoryTests(unittest.TestCase):
    def test_default_modes_use_mock_components(self) -> None:
        with (
            patch.object(settings, "sdr_mode", "mock"),
            patch.object(settings, "fpga_mode", "mock"),
        ):
            self.assertIsInstance(create_sdr_source(), MockSdrSource)
            self.assertIsInstance(create_fpga_transport(), MockFpgaTransport)

    def test_real_modes_use_hardware_components_and_settings(self) -> None:
        with (
            patch.object(settings, "sdr_mode", "real"),
            patch.object(settings, "sdr_sample_rate_hz", 1_024_000),
            patch.object(settings, "sdr_center_frequency_hz", 433_000_000),
            patch.object(settings, "sdr_gain", "20.5"),
            patch.object(settings, "fpga_mode", "real"),
            patch.object(settings, "spi_bus", 1),
            patch.object(settings, "spi_device", 2),
            patch.object(settings, "spi_max_speed_hz", 500_000),
            patch.object(settings, "spi_mode", 3),
        ):
            sdr = create_sdr_source()
            fpga = create_fpga_transport()

        self.assertIsInstance(sdr, RtlSdrSource)
        self.assertEqual(sdr.sample_rate_hz, 1_024_000)
        self.assertEqual(sdr.center_frequency_hz, 433_000_000)
        self.assertEqual(sdr.gain, 20.5)
        self.assertIsInstance(fpga, SpiFpgaTransport)
        self.assertEqual((fpga.bus, fpga.device), (1, 2))
        self.assertEqual(fpga.max_speed_hz, 500_000)
        self.assertEqual(fpga.mode, 3)

    def test_invalid_modes_are_rejected(self) -> None:
        with patch.object(settings, "sdr_mode", "wrong"):
            with self.assertRaises(ValueError):
                create_sdr_source()

        with patch.object(settings, "fpga_mode", "wrong"):
            with self.assertRaises(ValueError):
                create_fpga_transport()

    def test_invalid_sdr_gain_is_rejected(self) -> None:
        with (
            patch.object(settings, "sdr_mode", "real"),
            patch.object(settings, "sdr_gain", "wrong"),
        ):
            with self.assertRaisesRegex(ValueError, "SDR_GAIN"):
                create_sdr_source()


if __name__ == "__main__":
    unittest.main()
