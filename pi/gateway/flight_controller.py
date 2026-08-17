from __future__ import annotations

import threading
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
    position_measured_at: Optional[float] = None
    position_received_monotonic: Optional[float] = None


def update_telemetry_from_message(
    telemetry: FlightTelemetry,
    message: Any,
    received_at: Optional[float] = None,
    received_monotonic: Optional[float] = None,
) -> FlightTelemetry:
    """Update the latest telemetry using one MAVLink message."""

    message_type = message.get_type()

    if message_type == "GLOBAL_POSITION_INT":
        telemetry.latitude = message.lat / 1e7
        telemetry.longitude = message.lon / 1e7

        # The server expects non-negative flight altitude, so use height above
        # the takeoff/home position rather than mean-sea-level altitude.
        telemetry.altitude = max(0.0, message.relative_alt / 1000.0)
        telemetry.position_measured_at = (
            received_at if received_at is not None else time.time()
        )
        telemetry.position_received_monotonic = (
            received_monotonic
            if received_monotonic is not None
            else time.monotonic()
        )

    elif message_type == "SYS_STATUS":
        battery_remaining = int(message.battery_remaining)

        # MAVLink may use invalid/unknown values.
        # Only store a real percentage.
        if 0 <= battery_remaining <= 100:
            telemetry.battery = battery_remaining

    return telemetry


class FlightController:
    """Read MAVLink telemetry from the H743 flight controller."""

    POSITION_INTERVAL_US = 500_000
    SYSTEM_INTERVAL_US = 1_000_000

    MESSAGE_TYPES = (
        "GLOBAL_POSITION_INT",
        "SYS_STATUS",
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

        print(f"[MAVLink] connecting port={self.port} baud={self.baud_rate}")

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
            f"[MAVLink] connected system={self._connection.target_system} "
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

        # 2 Hz is enough for the gateway's default 2-second RSS cycle while
        # keeping the last position comfortably inside the freshness window.
        self._request_message_interval(
            self._mavutil.mavlink.MAVLINK_MSG_ID_GLOBAL_POSITION_INT,
            self.POSITION_INTERVAL_US,
        )

        # 1 Hz system/battery updates.
        self._request_message_interval(
            self._mavutil.mavlink.MAVLINK_MSG_ID_SYS_STATUS,
            self.SYSTEM_INTERVAL_US,
        )

        print(
            "[MAVLink] requested streams: "
            "GLOBAL_POSITION_INT=2Hz, "
            "SYS_STATUS=1Hz"
        )

    def messages(
        self,
        stop_event: Optional[threading.Event] = None,
    ) -> Iterator[Any]:
        """Yield relevant MAVLink messages, reconnecting if the link fails."""

        while stop_event is None or not stop_event.is_set():
            if self._connection is None:
                try:
                    self.connect()

                except KeyboardInterrupt:
                    raise

                except Exception as error:
                    print(f"[MAVLink] connection error: {error}")
                    print(
                        f"[MAVLink] retrying in "
                        f"{self.reconnect_delay_sec}s"
                    )

                    if stop_event is not None:
                        if stop_event.wait(self.reconnect_delay_sec):
                            break
                    else:
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
                print(f"[MAVLink] disconnected: {error}")

                self.close()

                print(
                    f"[MAVLink] retrying in {self.reconnect_delay_sec}s"
                )

                if stop_event is not None:
                    if stop_event.wait(self.reconnect_delay_sec):
                        break
                else:
                    time.sleep(self.reconnect_delay_sec)

    def telemetry(
        self,
        stop_event: Optional[threading.Event] = None,
    ) -> Iterator[FlightTelemetry]:
        """Yield accumulated flight telemetry once required fields exist."""

        latest = FlightTelemetry()

        for message in self.messages(stop_event):
            message_type = message.get_type()
            update_telemetry_from_message(
                latest,
                message,
            )

            # Battery messages update the accumulator. Publish a new snapshot
            # only for a new position so unchanged coordinates are not copied
            # and locked unnecessarily.
            if (
                message_type == "GLOBAL_POSITION_INT"
                and latest.position_measured_at is not None
                and latest.latitude is not None
                and latest.longitude is not None
                and latest.battery is not None
            ):
                yield FlightTelemetry(
                    latitude=latest.latitude,
                    longitude=latest.longitude,
                    altitude=latest.altitude,
                    battery=latest.battery,
                    position_measured_at=latest.position_measured_at,
                    position_received_monotonic=(
                        latest.position_received_monotonic
                    ),
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

        print("[MAVLink] connection closed")
