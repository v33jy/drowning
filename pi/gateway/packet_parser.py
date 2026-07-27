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
        raise PacketParseError("빈 패킷입니다.")

    parts = cleaned_packet.split(",")

    if len(parts) != 5:
        raise PacketParseError(
            f"패킷 항목은 5개여야 합니다. 현재 항목 수: {len(parts)}"
        )

    drone_id = parts[0].strip()

    if not drone_id:
        raise PacketParseError("드론 ID가 비어 있습니다.")

    try:
        rssi = int(parts[1])
        latitude = float(parts[2])
        longitude = float(parts[3])
        battery = int(parts[4])

    except ValueError as error:
        raise PacketParseError(
            "RSSI, 위도, 경도, 배터리는 숫자여야 합니다."
        ) from error

    if not -90 <= latitude <= 90:
        raise PacketParseError(
            f"위도 범위를 벗어났습니다: {latitude}"
        )

    if not -180 <= longitude <= 180:
        raise PacketParseError(
            f"경도 범위를 벗어났습니다: {longitude}"
        )

    if not 0 <= battery <= 100:
        raise PacketParseError(
            f"배터리는 0~100 사이여야 합니다: {battery}"
        )

    if not -150 <= rssi <= 0:
        raise PacketParseError(
            f"RSSI 값이 비정상적입니다: {rssi}"
        )

    return {
        "drone_id": drone_id,
        "rssi": rssi,
        "latitude": latitude,
        "longitude": longitude,
        "battery": battery,
        "received_at": datetime.now(timezone.utc).isoformat()
    }
