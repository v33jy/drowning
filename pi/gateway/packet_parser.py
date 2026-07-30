"""
Drone UART packet parser.

The packet format is a provisional assumption, not a spec confirmed with the
real HW (flight controller / RSSI board) — after connecting real hardware,
check raw packets with INPUT_MODE=raw_debug first, then adjust the field
count/order here if it differs.
"""

from datetime import datetime, timezone
from typing import Any


class PacketParseError(ValueError):
    """Raised when the packet format is invalid."""
    pass


def parse_packet(raw_packet: str) -> dict[str, Any]:
    """
    Convert a CSV drone packet into a dict.

    Example packet:
    drone-01,-65,37.5012,127.0324,87
    """

    cleaned_packet = raw_packet.strip()

    if not cleaned_packet:
        raise PacketParseError("Empty packet.")

    parts = cleaned_packet.split(",")

    if len(parts) != 5:
        raise PacketParseError(
            f"Packet must have 5 fields, got {len(parts)}."
        )

    drone_id = parts[0].strip()

    if not drone_id:
        raise PacketParseError("Drone ID is empty.")

    try:
        rssi = int(parts[1])
        latitude = float(parts[2])
        longitude = float(parts[3])
        battery = int(parts[4])

    except ValueError as error:
        raise PacketParseError(
            "RSSI, latitude, longitude, and battery must be numeric."
        ) from error

    if not -90 <= latitude <= 90:
        raise PacketParseError(
            f"Latitude out of range: {latitude}"
        )

    if not -180 <= longitude <= 180:
        raise PacketParseError(
            f"Longitude out of range: {longitude}"
        )

    if not 0 <= battery <= 100:
        raise PacketParseError(
            f"Battery must be between 0 and 100: {battery}"
        )

    if not -150 <= rssi <= 0:
        raise PacketParseError(
            f"RSSI value out of range: {rssi}"
        )

    return {
        "drone_id": drone_id,
        "rssi": rssi,
        "latitude": latitude,
        "longitude": longitude,
        "battery": battery,
        "received_at": datetime.now(timezone.utc).isoformat()
    }
