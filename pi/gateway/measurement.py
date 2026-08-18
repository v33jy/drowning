from dataclasses import dataclass
from typing import Any, Optional


@dataclass(frozen=True)
class SignalMeasurement:
    """One RSS result produced by the SDR/FPGA pipeline."""

    rss_dbm: float
    measured_at: float

    def __post_init__(self) -> None:
        if self.rss_dbm > 0:
            raise ValueError("rss_dbm must be zero or less")
        if self.measured_at < 0:
            raise ValueError("measured_at must be zero or greater")


@dataclass(frozen=True)
class SignalObservation:
    """One RSS measurement combined with the matching flight position."""

    drone_id: str
    rss_dbm: float
    latitude: float
    longitude: float
    altitude: float
    battery: Optional[int]
    signal_measured_at: float
    position_measured_at: float

    def __post_init__(self) -> None:
        if not self.drone_id:
            raise ValueError("drone_id must not be empty")
        if self.rss_dbm > 0:
            raise ValueError("rss_dbm must be zero or less")
        if not -90 <= self.latitude <= 90:
            raise ValueError("latitude must be between -90 and 90")
        if not -180 <= self.longitude <= 180:
            raise ValueError("longitude must be between -180 and 180")
        if self.altitude < 0:
            raise ValueError("altitude must be zero or greater")
        if self.battery is not None and not 0 <= self.battery <= 100:
            raise ValueError("battery must be between 0 and 100")
        if self.signal_measured_at < 0 or self.position_measured_at < 0:
            raise ValueError("measurement times must be zero or greater")

    def telemetry_payload(self) -> dict[str, Any]:
        return {
            "drone_id": self.drone_id,
            "latitude": self.latitude,
            "longitude": self.longitude,
            "altitude": self.altitude,
            "battery": self.battery,
            "status": "active",
        }
