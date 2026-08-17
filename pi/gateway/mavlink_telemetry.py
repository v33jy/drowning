from __future__ import annotations

import threading
import time
from dataclasses import replace
from typing import Optional

from flight_controller import FlightController, FlightTelemetry
from measurement import SignalMeasurement, SignalObservation


def combine_measurements(
    signal: SignalMeasurement,
    flight_data: FlightTelemetry,
    drone_id: str,
) -> SignalObservation:
    """Combine one SDR/FPGA result with a complete H743 snapshot."""
    if (
        flight_data.latitude is None
        or flight_data.longitude is None
        or flight_data.battery is None
        or flight_data.position_measured_at is None
    ):
        raise ValueError("Flight telemetry is incomplete")

    return SignalObservation(
        drone_id=drone_id,
        rss_dbm=signal.rss_dbm,
        latitude=flight_data.latitude,
        longitude=flight_data.longitude,
        altitude=(
            flight_data.altitude
            if flight_data.altitude is not None
            else 0.0
        ),
        battery=flight_data.battery,
        signal_measured_at=signal.measured_at,
        position_measured_at=flight_data.position_measured_at,
    )


class MavlinkTelemetryService:
    """Read MAVLink in the background and expose the latest flight data."""

    def __init__(
        self,
        port: str,
        baud_rate: int,
        reconnect_delay_sec: float,
    ) -> None:
        self._controller = FlightController(
            port=port,
            baud_rate=baud_rate,
            reconnect_delay_sec=reconnect_delay_sec,
        )
        self._latest: Optional[FlightTelemetry] = None
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._thread: Optional[threading.Thread] = None

    def start(self) -> None:
        if self._thread is not None:
            return

        self._thread = threading.Thread(
            target=self._read_loop,
            name="mavlink-telemetry",
            daemon=True,
        )
        self._thread.start()

    def _read_loop(self) -> None:
        for telemetry in self._controller.telemetry(self._stop_event):
            with self._lock:
                self._latest = telemetry

    def latest(
        self,
        max_position_age_sec: float,
        now_monotonic: Optional[float] = None,
    ) -> Optional[FlightTelemetry]:
        with self._lock:
            if self._latest is None:
                return None
            latest = replace(self._latest)

        if latest.position_received_monotonic is None:
            return None

        current_time = (
            time.monotonic()
            if now_monotonic is None
            else now_monotonic
        )
        position_age = current_time - latest.position_received_monotonic
        if position_age > max_position_age_sec:
            return None

        return latest

    def close(self) -> None:
        self._stop_event.set()
        self._controller.close()

        if self._thread is not None:
            self._thread.join(timeout=2)
            self._thread = None
