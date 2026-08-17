import unittest
from unittest.mock import MagicMock, patch

import mavlink_telemetry
from flight_controller import FlightTelemetry
from measurement import SignalMeasurement, SignalObservation


class CombineMeasurementsTests(unittest.TestCase):
    def test_combines_signal_and_flight_measurements(self) -> None:
        signal = SignalMeasurement(rss_dbm=-65.25, measured_at=124.0)
        flight_data = FlightTelemetry(
            latitude=37.5012,
            longitude=127.0324,
            altitude=50.0,
            battery=87,
            position_measured_at=123.0,
        )

        combined = mavlink_telemetry.combine_measurements(
            signal,
            flight_data,
            "drone-02",
        )

        self.assertEqual(
            combined,
            SignalObservation(
                drone_id="drone-02",
                rss_dbm=-65.25,
                latitude=37.5012,
                longitude=127.0324,
                altitude=50.0,
                battery=87,
                signal_measured_at=124.0,
                position_measured_at=123.0,
            ),
        )

    def test_uses_zero_altitude_when_missing(self) -> None:
        combined = mavlink_telemetry.combine_measurements(
            SignalMeasurement(rss_dbm=-65.0, measured_at=124.0),
            FlightTelemetry(
                latitude=37.5012,
                longitude=127.0324,
                altitude=None,
                battery=87,
                position_measured_at=123.0,
            ),
            "drone-01",
        )

        self.assertEqual(combined.altitude, 0.0)

    def test_rejects_incomplete_flight_telemetry(self) -> None:
        with self.assertRaisesRegex(ValueError, "incomplete"):
            mavlink_telemetry.combine_measurements(
                SignalMeasurement(rss_dbm=-65.0, measured_at=124.0),
                FlightTelemetry(latitude=37.5012),
                "drone-01",
            )


class MavlinkTelemetryServiceTests(unittest.TestCase):
    def test_builds_controller_from_hardware_settings(self) -> None:
        fake_controller = MagicMock()

        with patch.object(
            mavlink_telemetry,
            "FlightController",
            return_value=fake_controller,
        ) as controller_class:
            service = mavlink_telemetry.MavlinkTelemetryService(
                port="/dev/serial0",
                baud_rate=115200,
                reconnect_delay_sec=4.0,
            )

        controller_class.assert_called_once_with(
            port="/dev/serial0",
            baud_rate=115200,
            reconnect_delay_sec=4.0,
        )
        self.assertIs(service._controller, fake_controller)

    def test_latest_rejects_stale_position(self) -> None:
        service = mavlink_telemetry.MavlinkTelemetryService(
            port="/dev/serial0",
            baud_rate=115200,
            reconnect_delay_sec=4.0,
        )
        service._latest = FlightTelemetry(
            latitude=37.5012,
            longitude=127.0324,
            altitude=50.0,
            battery=87,
            position_measured_at=100.0,
            position_received_monotonic=200.0,
        )

        self.assertIsNone(
            service.latest(
                max_position_age_sec=3.0,
                now_monotonic=204.0,
            )
        )

    def test_latest_returns_fresh_position_copy(self) -> None:
        service = mavlink_telemetry.MavlinkTelemetryService(
            port="/dev/serial0",
            baud_rate=115200,
            reconnect_delay_sec=4.0,
        )
        service._latest = FlightTelemetry(
            latitude=37.5012,
            longitude=127.0324,
            altitude=50.0,
            battery=87,
            position_measured_at=100.0,
            position_received_monotonic=200.0,
        )

        latest = service.latest(
            max_position_age_sec=3.0,
            now_monotonic=202.0,
        )

        self.assertEqual(latest, service._latest)
        self.assertIsNot(latest, service._latest)


if __name__ == "__main__":
    unittest.main()
