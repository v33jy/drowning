import unittest
from unittest.mock import MagicMock

from flight_controller import (
    FlightController,
    FlightTelemetry,
    update_telemetry_from_message,
)


class FakeMessage:
    def __init__(self, message_type: str, **fields) -> None:
        self._message_type = message_type

        for name, value in fields.items():
            setattr(self, name, value)

    def get_type(self) -> str:
        return self._message_type


class FlightControllerTelemetryTests(unittest.TestCase):
    def test_global_position_int_updates_position(self) -> None:
        telemetry = FlightTelemetry()

        message = FakeMessage(
            "GLOBAL_POSITION_INT",
            lat=375012000,
            lon=1270324000,
            alt=50000,
            relative_alt=12300,
        )

        update_telemetry_from_message(
            telemetry,
            message,
            received_at=123.0,
            received_monotonic=456.0,
        )

        self.assertAlmostEqual(telemetry.latitude, 37.5012)
        self.assertAlmostEqual(telemetry.longitude, 127.0324)
        self.assertAlmostEqual(telemetry.altitude, 12.3)
        self.assertEqual(telemetry.position_measured_at, 123.0)
        self.assertEqual(telemetry.position_received_monotonic, 456.0)

    def test_sys_status_updates_battery(self) -> None:
        telemetry = FlightTelemetry()

        message = FakeMessage(
            "SYS_STATUS",
            battery_remaining=87,
        )

        update_telemetry_from_message(telemetry, message)

        self.assertEqual(telemetry.battery, 87)

    def test_unknown_battery_clears_stale_percentage(self) -> None:
        telemetry = FlightTelemetry(
            battery=50,
        )

        message = FakeMessage(
            "SYS_STATUS",
            battery_remaining=-1,
        )

        update_telemetry_from_message(telemetry, message)

        self.assertIsNone(telemetry.battery)

    def test_publishes_snapshot_only_for_new_position(self) -> None:
        controller = FlightController("/dev/serial0")
        controller.messages = MagicMock(return_value=iter([
            FakeMessage("SYS_STATUS", battery_remaining=87),
            FakeMessage(
                "GLOBAL_POSITION_INT",
                lat=375012000,
                lon=1270324000,
                alt=50000,
                relative_alt=12300,
            ),
            FakeMessage("SYS_STATUS", battery_remaining=86),
        ]))

        snapshots = list(controller.telemetry())

        self.assertEqual(len(snapshots), 1)
        self.assertEqual(snapshots[0].battery, 87)

    def test_publishes_position_when_battery_is_unknown(self) -> None:
        controller = FlightController("/dev/serial0")
        controller.messages = MagicMock(return_value=iter([
            FakeMessage("SYS_STATUS", battery_remaining=-1),
            FakeMessage(
                "GLOBAL_POSITION_INT",
                lat=375012000,
                lon=1270324000,
                alt=50000,
                relative_alt=12300,
            ),
        ]))

        snapshots = list(controller.telemetry())

        self.assertEqual(len(snapshots), 1)
        self.assertIsNone(snapshots[0].battery)

if __name__ == "__main__":
    unittest.main()
