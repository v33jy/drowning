import unittest
from unittest.mock import patch

import main as gateway_main
from config import settings


class InputModeTests(unittest.TestCase):
    def test_signal_pipeline_mode_uses_pipeline_generator(self) -> None:
        expected = iter(["packet"])
        with (
            patch.object(settings, "input_mode", "signal_pipeline"),
            patch.object(
                gateway_main,
                "generate_signal_pipeline_packets",
                return_value=expected,
            ),
        ):
            self.assertIs(gateway_main.get_packet_source(), expected)

    def test_signal_pipeline_uses_rss_detection_fallback(self) -> None:
        with (
            patch.object(settings, "input_mode", "signal_pipeline"),
            patch.object(settings, "detection_mode", "fpga"),
        ):
            self.assertTrue(gateway_main.uses_rss_detection())

    def test_serial_fpga_mode_does_not_use_rss_fallback(self) -> None:
        with (
            patch.object(settings, "input_mode", "serial"),
            patch.object(settings, "detection_mode", "fpga"),
        ):
            self.assertFalse(gateway_main.uses_rss_detection())


if __name__ == "__main__":
    unittest.main()
