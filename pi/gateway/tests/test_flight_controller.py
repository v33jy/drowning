import math
import unittest

from flight_controller import FlightTelemetry, update_telemetry_from_message


class FakeMessage:
    def __init__(self, message_type: str, **fields) -> None:
        self._message_type = message_type

        for name, value in fields.items():
            setattr(self, name, value)

    def get_type(self) -> str:
        return self._message_type


class FlightControllerTelemetryTests(unittest.TestCase):
    def test_global_position_int_updates_position_and_speed(self) -> None:
        telemetry = FlightTelemetry()

        message = FakeMessage(
            "GLOBAL_POSITION_INT",
            lat=375012000,
            lon=1270324000,
            alt=50000,
            vx=300,
            vy=400,
            vz=-200,
        )

        update_telemetry_from_message(telemetry, message)

        self.assertAlmostEqual(telemetry.latitude, 37.5012)
        self.assertAlmostEqual(telemetry.longitude, 127.0324)
        self.assertAlmostEqual(telemetry.altitude, 50.0)

        self.assertAlmostEqual(telemetry.ground_speed, 5.0)
        self.assertAlmostEqual(telemetry.vertical_speed, 2.0)

    def test_sys_status_updates_battery(self) -> None:
        telemetry = FlightTelemetry()

        message = FakeMessage(
            "SYS_STATUS",
            battery_remaining=87,
        )

        update_telemetry_from_message(telemetry, message)

        self.assertEqual(telemetry.battery, 87)

    def test_invalid_battery_is_ignored(self) -> None:
        telemetry = FlightTelemetry(
            battery=50,
        )

        message = FakeMessage(
            "SYS_STATUS",
            battery_remaining=-1,
        )

        update_telemetry_from_message(telemetry, message)

        self.assertEqual(telemetry.battery, 50)

    def test_attitude_converts_radians_to_degrees(self) -> None:
        telemetry = FlightTelemetry()

        message = FakeMessage(
            "ATTITUDE",
            roll=math.radians(10),
            pitch=math.radians(-5),
            yaw=math.radians(90),
        )

        update_telemetry_from_message(telemetry, message)

        self.assertAlmostEqual(telemetry.roll, 10.0)
        self.assertAlmostEqual(telemetry.pitch, -5.0)
        self.assertAlmostEqual(telemetry.yaw, 90.0)


if __name__ == "__main__":
    unittest.main()
    '''GLOBAL_POSITION_INT가 들어오면 위도/경도/고도/속도가 우리가 원하는 단위로 바뀌는지 확인
SYS_STATUS에서 배터리 %가 제대로 들어오는지 확인
MAVLink에서 배터리 unknown 값으로 흔히 쓰는 -1 같은 값은 기존 값을 덮어쓰지 않는지 확인
ATTITUDE의 rad 값을 degree로 제대로 바꾸는지 확인'''