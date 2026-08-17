import unittest
from unittest.mock import MagicMock, patch

import main as gateway_main
from config import settings
from flight_controller import FlightTelemetry
from measurement import SignalMeasurement


class InputModeTests(unittest.TestCase):
    def test_signal_pipeline_mode_uses_signal_measurements(self) -> None:
        expected = iter([
            SignalMeasurement(rss_dbm=-65.0, measured_at=123.0)
        ])

        with (
            patch.object(settings, "input_mode", "signal_pipeline"),
            patch.object(
                gateway_main,
                "generate_signal_measurements",
                return_value=expected,
            ),
        ):
            self.assertIs(
                gateway_main.get_measurement_source(),
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

    def test_main_combines_signal_packet_with_mavlink_telemetry(self) -> None:
        fake_reader = MagicMock()
        fake_reader.latest.return_value = FlightTelemetry(
            latitude=37.5012,
            longitude=127.0324,
            altitude=50.0,
            battery=87,
            position_measured_at=122.5,
            position_received_monotonic=500.0,
        )
        fake_client = MagicMock()
        fake_client.send_telemetry.return_value = {"cell_id": "A1"}

        with (
            patch.object(settings, "input_mode", "signal_pipeline"),
            patch.object(settings, "detection_mode", "rss_threshold"),
            patch.object(settings, "rss_detection_threshold", -40.0),
            patch.object(
                gateway_main,
                "MavlinkTelemetryService",
                return_value=fake_reader,
            ) as service_class,
            patch.object(
                gateway_main,
                "get_measurement_source",
                return_value=iter([
                    SignalMeasurement(
                        rss_dbm=-65.25,
                        measured_at=123.0,
                    ),
                ]),
            ),
            patch.object(
                gateway_main,
                "GatewayClient",
                return_value=fake_client,
            ),
        ):
            gateway_main.main()

        service_class.assert_called_once_with(
            port=settings.fc_serial_port,
            baud_rate=settings.fc_baud_rate,
            reconnect_delay_sec=settings.fc_reconnect_delay_sec,
        )
        fake_reader.start.assert_called_once_with()
        fake_reader.close.assert_called_once_with()
        fake_reader.latest.assert_called_once_with(
            settings.fc_position_max_age_sec
        )
        fake_client.send_telemetry.assert_called_once_with(
            {
                "drone_id": "drone-01",
                "latitude": 37.5012,
                "longitude": 127.0324,
                "battery": 87,
                "altitude": 50.0,
                "status": "active",
            }
        )
        fake_client.send_signal.assert_called_once_with(
            1,
            -65.25,
            lat=37.5012,
            lng=127.0324,
            altitude=50.0,
            measured_at=123.0,
        )


if __name__ == "__main__":
    unittest.main()
