from __future__ import annotations

import math
import time
from dataclasses import dataclass
from typing import Any, Iterator, Optional


@dataclass
class FlightTelemetry:
    """Latest flight-controller telemetry decoded from MAVLink."""

    latitude: Optional[float] = None
    longitude: Optional[float] = None
    altitude: Optional[float] = None
    battery: Optional[int] = None

    ground_speed: Optional[float] = None
    vertical_speed: Optional[float] = None

    roll: Optional[float] = None
    pitch: Optional[float] = None
    yaw: Optional[float] = None


def update_telemetry_from_message(
    telemetry: FlightTelemetry,
    message: Any,
) -> FlightTelemetry:
    """Update the latest telemetry using one MAVLink message."""

    message_type = message.get_type()

    if message_type == "GLOBAL_POSITION_INT":
        telemetry.latitude = message.lat / 1e7
        telemetry.longitude = message.lon / 1e7

        # GLOBAL_POSITION_INT.alt is millimetres above mean sea level.
        telemetry.altitude = message.alt / 1000.0

        # vx, vy, vz are centimetres per second in NED coordinates.
        vx = message.vx / 100.0
        vy = message.vy / 100.0

        telemetry.ground_speed = math.hypot(vx, vy)

        # MAVLink NED:
        # positive Z velocity means downward.
        # Convert to positive-up vertical speed for our application.
        telemetry.vertical_speed = -(message.vz / 100.0)

    elif message_type == "SYS_STATUS":
        battery_remaining = int(message.battery_remaining)

        # MAVLink may use invalid/unknown values.
        # Only store a real percentage.
        if 0 <= battery_remaining <= 100:
            telemetry.battery = battery_remaining

    elif message_type == "ATTITUDE":
        # MAVLink ATTITUDE angles are radians.
        telemetry.roll = math.degrees(message.roll)
        telemetry.pitch = math.degrees(message.pitch)
        telemetry.yaw = math.degrees(message.yaw)

    return telemetry


class FlightController:
    """Read MAVLink telemetry from the H743 flight controller."""

    MESSAGE_TYPES = (
        "GLOBAL_POSITION_INT",
        "SYS_STATUS",
        "ATTITUDE",
    )

    def __init__(
        self,
        port: str,
        baud_rate: int = 115200,
        heartbeat_timeout_sec: float = 10.0,
        reconnect_delay_sec: float = 3.0,
    ) -> None:
        self.port = port
        self.baud_rate = baud_rate
        self.heartbeat_timeout_sec = heartbeat_timeout_sec
        self.reconnect_delay_sec = reconnect_delay_sec

        self._connection = None
        self._mavutil = None

    def connect(self) -> None:
        """Open the MAVLink serial link and wait for the H743 heartbeat."""

        try:
            from pymavlink import mavutil

        except ImportError as error:
            raise RuntimeError(
                "pymavlink is not installed. "
                "Install pi/gateway/requirements-hardware.txt."
            ) from error

        self._mavutil = mavutil

        print(
            "[flight controller connecting] "
            f"port={self.port}, "
            f"baud={self.baud_rate}"
        )

        self._connection = mavutil.mavlink_connection(
            self.port,
            baud=self.baud_rate,
        )

        heartbeat = self._connection.wait_heartbeat(
            timeout=self.heartbeat_timeout_sec
        )

        if heartbeat is None:
            self.close()

            raise TimeoutError(
                "No MAVLink heartbeat received from the flight controller "
                f"within {self.heartbeat_timeout_sec} seconds."
            )

        print(
            "[flight controller connected] "
            f"system={self._connection.target_system}, "
            f"component={self._connection.target_component}"
        )

        self._request_message_streams()

    def _request_message_interval(
        self,
        message_id: int,
        interval_us: int,
    ) -> None:
        """Ask the flight controller to send one MAVLink message periodically."""

        if self._connection is None or self._mavutil is None:
            return

        self._connection.mav.command_long_send(
            self._connection.target_system,
            self._connection.target_component,
            self._mavutil.mavlink.MAV_CMD_SET_MESSAGE_INTERVAL,
            0,
            message_id,
            interval_us,
            0,
            0,
            0,
            0,
            0,
        )

    def _request_message_streams(self) -> None:
        """Request the MAVLink telemetry required by the gateway."""

        if self._mavutil is None:
            return

        # 5 Hz position updates.
        self._request_message_interval(
            self._mavutil.mavlink.MAVLINK_MSG_ID_GLOBAL_POSITION_INT,
            200_000,
        )

        # 1 Hz system/battery updates.
        self._request_message_interval(
            self._mavutil.mavlink.MAVLINK_MSG_ID_SYS_STATUS,
            1_000_000,
        )

        # 5 Hz attitude updates.
        self._request_message_interval(
            self._mavutil.mavlink.MAVLINK_MSG_ID_ATTITUDE,
            200_000,
        )

        print(
            "[flight controller] requested MAVLink streams: "
            "GLOBAL_POSITION_INT=5Hz, "
            "SYS_STATUS=1Hz, "
            "ATTITUDE=5Hz"
        )

    def messages(self) -> Iterator[Any]:
        """Yield relevant MAVLink messages, reconnecting if the link fails."""

        while True:
            if self._connection is None:
                try:
                    self.connect()

                except KeyboardInterrupt:
                    raise

                except Exception as error:
                    print(
                        f"[flight controller connection error] {error}"
                    )
                    print(
                        "[flight controller] "
                        f"retrying in {self.reconnect_delay_sec}s"
                    )

                    time.sleep(self.reconnect_delay_sec)
                    continue

            try:
                message = self._connection.recv_match(
                    type=list(self.MESSAGE_TYPES),
                    blocking=True,
                    timeout=1,
                )

                if message is None:
                    continue

                if message.get_type() == "BAD_DATA":
                    continue

                yield message

            except KeyboardInterrupt:
                raise

            except Exception as error:
                print(
                    f"[flight controller disconnected] {error}"
                )

                self.close()

                print(
                    "[flight controller] "
                    f"retrying in {self.reconnect_delay_sec}s"
                )

                time.sleep(self.reconnect_delay_sec)

    def telemetry(self) -> Iterator[FlightTelemetry]:
        """Yield accumulated flight telemetry once required fields exist."""

        latest = FlightTelemetry()

        for message in self.messages():
            update_telemetry_from_message(
                latest,
                message,
            )

            if (
                latest.latitude is not None
                and latest.longitude is not None
                and latest.battery is not None
            ):
                yield FlightTelemetry(
                    latitude=latest.latitude,
                    longitude=latest.longitude,
                    altitude=latest.altitude,
                    battery=latest.battery,
                    ground_speed=latest.ground_speed,
                    vertical_speed=latest.vertical_speed,
                    roll=latest.roll,
                    pitch=latest.pitch,
                    yaw=latest.yaw,
                )

    def close(self) -> None:
        """Close the underlying MAVLink serial connection."""

        if self._connection is None:
            return

        close = getattr(
            self._connection,
            "close",
            None,
        )

        if close is not None:
            close()

        self._connection = None

        print("[flight controller connection closed]")