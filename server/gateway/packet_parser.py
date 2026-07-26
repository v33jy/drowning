"""
드론 UART 패킷 파서.

패킷 포맷은 실제 HW(비행 컨트롤러/RSSI 센서 보드)와 확정된 스펙이 아니라
잠정 가정임 — 실기기 연결 후 INPUT_MODE=raw_debug로 원본 패킷을 먼저 확인하고,
다르면 이 파일의 필드 개수/순서만 고치면 됨.
"""

from datetime import datetime, timezone
from typing import Any


class PacketParseError(ValueError):
    """패킷 형식이 잘못됐을 때 발생하는 오류."""
    pass


def parse_packet(raw_packet: str) -> dict[str, Any]:
    """
    CSV 형식의 드론 패킷을 딕셔너리로 변환한다.

    패킷 예시:
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
