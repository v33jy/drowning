import unittest
from unittest.mock import MagicMock, patch

import main as gateway_main
from config import settings
from flight_controller import FlightTelemetry


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
            self.assertIs(
                gateway_main.get_packet_source(),
                expected,
            )

    def test_signal_pipeline_uses_rss_detection_fallback(self) -> None:
        with (
            patch.object(settings, "input_mode", "signal_pipeline"),
            patch.object(settings, "detection_mode", "fpga"),
        ):
            self.assertTrue(
                gateway_main.uses_rss_detection()
            )

    def test_serial_fpga_mode_does_not_use_rss_fallback(self) -> None:
        with (
            patch.object(settings, "input_mode", "serial"),
            patch.object(settings, "detection_mode", "fpga"),
        ):
            self.assertFalse(
                gateway_main.uses_rss_detection()
            )

    def test_mavlink_mode_forwards_flight_telemetry_to_server(self) -> None:
        fake_flight_data = FlightTelemetry(
            latitude=37.5012,
            longitude=127.0324,
            altitude=50.0,
            battery=87,
            ground_speed=5.0,
            vertical_speed=1.5,
            roll=10.0,
            pitch=-5.0,
            yaw=90.0,
        )

        fake_controller = MagicMock()
        fake_controller.telemetry.return_value = iter(
            [fake_flight_data]
        )

        fake_client = MagicMock()

        with (
            patch.object(
                settings,
                "fc_serial_port",
                "/dev/serial0",
            ),
            patch.object(
                settings,
                "fc_baud_rate",
                115200,
            ),
            patch.object(
                gateway_main,
                "FlightController",
                return_value=fake_controller,
            ) as controller_class,
        ):
            gateway_main.run_mavlink_telemetry(
                fake_client
            )

        controller_class.assert_called_once_with(
            port="/dev/serial0",
            baud_rate=115200,
        )

        fake_client.send_telemetry.assert_called_once_with(
            {
                "drone_id": "drone-01",
                "latitude": 37.5012,
                "longitude": 127.0324,
                "altitude": 50.0,
                "battery": 87,
                "status": "active",
            }
        )

    def test_mavlink_mode_uses_zero_altitude_when_missing(self) -> None:
        fake_flight_data = FlightTelemetry(
            latitude=37.5012,
            longitude=127.0324,
            altitude=None,
            battery=87,
        )

        fake_controller = MagicMock()
        fake_controller.telemetry.return_value = iter(
            [fake_flight_data]
        )

        fake_client = MagicMock()

        with patch.object(
            gateway_main,
            "FlightController",
            return_value=fake_controller,
        ):
            gateway_main.run_mavlink_telemetry(
                fake_client
            )

        fake_client.send_telemetry.assert_called_once_with(
            {
                "drone_id": "drone-01",
                "latitude": 37.5012,
                "longitude": 127.0324,
                "altitude": 0.0,
                "battery": 87,
                "status": "active",
            }
        )


if __name__ == "__main__":
    unittest.main()