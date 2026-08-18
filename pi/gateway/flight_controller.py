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

        # MAVLink uses -1 when the battery monitor is unavailable.
        # Store None instead of retaining a stale battery percentage.
        telemetry.battery = (
            battery_remaining
            if 0 <= battery_remaining <= 100
            else None
        )

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
        message_timeout_sec: float = 10.0,
        reconnect_delay_sec: float = 3.0,
    ) -> None:
        self.port = port
        self.baud_rate = baud_rate
        self.heartbeat_timeout_sec = heartbeat_timeout_sec
        self.message_timeout_sec = message_timeout_sec
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
            f"[MAVLink] connecting port={self.port} "
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

        # Request position updates at 2 Hz.
        self._request_message_interval(
            self._mavutil.mavlink.MAVLINK_MSG_ID_GLOBAL_POSITION_INT,
            self.POSITION_INTERVAL_US,
        )

        # Request system and battery updates at 1 Hz.
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
        """Yield MAVLink messages and reconnect when telemetry becomes silent."""

        last_message_received_monotonic = time.monotonic()

        while stop_event is None or not stop_event.is_set():
            if self._connection is None:
                try:
                    self.connect()
                    last_message_received_monotonic = time.monotonic()

                except KeyboardInterrupt:
                    raise

                except Exception as error:
                    print(f"[MAVLink] connection error: {error}")
                    print(
                        "[MAVLink] retrying in "
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
                    silence_sec = (
                        time.monotonic()
                        - last_message_received_monotonic
                    )

                    if silence_sec >= self.message_timeout_sec:
                        print(
                            "[MAVLink] no telemetry received for "
                            f"{silence_sec:.1f}s; reconnecting"
                        )
                        self.close()

                    continue

                if message.get_type() == "BAD_DATA":
                    continue

                last_message_received_monotonic = time.monotonic()
                yield message

            except KeyboardInterrupt:
                raise

            except Exception as error:
                print(f"[MAVLink] disconnected: {error}")

                self.close()

                print(
                    "[MAVLink] retrying in "
                    f"{self.reconnect_delay_sec}s"
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

            # Battery messages update the accumulator. Publish a snapshot only
            # when a new position arrives.
            if (
                message_type == "GLOBAL_POSITION_INT"
                and latest.position_measured_at is not None
                and latest.latitude is not None
                and latest.longitude is not None
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