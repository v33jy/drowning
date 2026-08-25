"""지도 중요도 + RSSI 후보 셀 순차 확인 데모.

시작 시 기존 수색 결과처럼 히트맵과 후보 셀을 준비한다. 드론은 서버가
계산한 1번 후보부터 부드럽게 이동하고, 도착 팝업에서 구조자가 판정하면
다음 후보로 출발한다.
"""

from __future__ import annotations

import asyncio
import math
import os
from typing import Any

import httpx

import config
from route_planner import cell_center

SERVER_URL = os.environ.get("DRONE_SERVER_URL", "http://localhost:8001")
DRONE_ID = int(os.environ.get("DRONE_ID", "1"))
MOVE_INTERVAL = float(os.environ.get("SCENARIO_MOVE_INTERVAL", "0.12"))
METERS_PER_STEP = float(os.environ.get("SCENARIO_METERS_PER_STEP", "18"))
ALTITUDE = 35.0

CANDIDATE_RSSI = {
    "D3": -61.0,
    "F2": -63.0,
    "E5": -59.0,
    "H8": -56.0,
    "C9": -52.0,
}


async def run() -> None:
    async with httpx.AsyncClient(base_url=SERVER_URL, timeout=5.0) as client:
        _banner("재난 지역 후보 셀 순차 확인 시나리오")
        start = cell_center("A0")
        battery = 100.0
        await _telemetry(client, *start, battery)
        await _seed_existing_search(client)
        await asyncio.sleep(1.0)

        route = await _route(client)
        if not route:
            print("후보 셀이 없습니다. 서버를 재시작한 뒤 다시 실행하세요.")
            return

        print("\n[초기 화면 준비 완료]")
        print("  지도 중요도 + 기존 RSSI 히트맵 표시")
        print("  후보 방문 순서:", " → ".join(route))
        print("  드론이 1번 후보로 출발합니다.\n")

        current = start
        for number, cell_id in enumerate(route, start=1):
            target = cell_center(cell_id)
            print(f"[{number}번] {cell_id} 후보 셀로 이동")
            current, battery = await _fly_smoothly(
                client, current, target, battery
            )
            await asyncio.sleep(1.2)
            print("  도착: 영상 팝업에서 오탐 또는 요구조자 발견을 선택하세요.")

            outcome = await _wait_for_review(client, cell_id, battery, current)
            if outcome == "survivor_confirmed":
                _banner(f"요구조자 발견 — {number}번 {cell_id} 셀")
                print("현장에서 호버링하며 영상·음성 연결을 유지합니다.")
                await _hover(client, current, battery)
                return
            print("  오탐 처리 완료 — 다음 후보로 이동합니다.\n")

        print("모든 후보 확인이 끝났습니다.")


async def _seed_existing_search(client: httpx.AsyncClient) -> None:
    print("[초기화] 지도 중요도와 기존 RSSI 측정 결과를 결합합니다.")
    # 1차 수색이 끝난 시점이므로 전체 셀에 최소 한 개의 RSSI 표본이 있다.
    # 후보가 아닌 셀도 주변 통과 측정값으로 채워 미확인 공백을 남기지 않는다.
    baseline = {
        f"{chr(65 + row)}{col}": -96.0 + ((row * 7 + col * 3) % 18)
        for row in range(config.GRID_ROWS)
        for col in range(config.GRID_COLS)
    }
    for cell_id, rss in baseline.items():
        lat, lng = cell_center(cell_id)
        response = await client.post(
            f"/drones/{DRONE_ID}/signal",
            json={
                "measurement_id": f"scenario-sweep-{cell_id}",
                "rss_dbm": rss,
                "lat": lat,
                "lng": lng,
                "altitude": ALTITUDE,
            },
        )
        response.raise_for_status()

    for cell_id, rss in CANDIDATE_RSSI.items():
        lat, lng = cell_center(cell_id)
        for sample in range(3):
            response = await client.post(
                f"/drones/{DRONE_ID}/signal",
                json={
                    "measurement_id": f"scenario-candidate-{cell_id}-{sample}",
                    "rss_dbm": rss - sample * 0.4,
                    "lat": lat,
                    "lng": lng,
                    "altitude": ALTITUDE,
                },
            )
            response.raise_for_status()


async def _route(client: httpx.AsyncClient) -> list[str]:
    response = await client.post("/search/route", json={"drone_id": DRONE_ID})
    response.raise_for_status()
    return response.json()["order"]


async def _fly_smoothly(
    client: httpx.AsyncClient,
    start: tuple[float, float],
    target: tuple[float, float],
    battery: float,
) -> tuple[tuple[float, float], float]:
    steps = max(8, math.ceil(_distance_meters(start, target) / METERS_PER_STEP))
    for step in range(1, steps + 1):
        progress = step / steps
        eased = progress * progress * (3 - 2 * progress)
        lat = start[0] + (target[0] - start[0]) * eased
        lng = start[1] + (target[1] - start[1]) * eased
        battery = max(10.0, battery - 0.035)
        await _telemetry(client, lat, lng, battery)
        await asyncio.sleep(MOVE_INTERVAL)
    return target, battery


async def _wait_for_review(
    client: httpx.AsyncClient,
    cell_id: str,
    battery: float,
    position: tuple[float, float],
) -> str:
    while True:
        await _telemetry(client, *position, battery)
        response = await client.get("/state")
        response.raise_for_status()
        cells = response.json().get("heatmap", [])
        cell: dict[str, Any] | None = next(
            (item for item in cells if item.get("cell_id") == cell_id), None
        )
        status = None if cell is None else cell.get("status")
        if status == "cleared":
            return "false_alarm"
        if status == "confirmed":
            return "survivor_confirmed"
        await asyncio.sleep(0.8)


async def _hover(
    client: httpx.AsyncClient,
    position: tuple[float, float],
    battery: float,
) -> None:
    while True:
        battery = max(10.0, battery - 0.02)
        await _telemetry(client, *position, battery)
        await asyncio.sleep(2.0)


async def _telemetry(
    client: httpx.AsyncClient, lat: float, lng: float, battery: float
) -> None:
    response = await client.post(
        f"/drones/{DRONE_ID}/telemetry",
        json={
            "lat": round(lat, 7),
            "lng": round(lng, 7),
            "altitude": ALTITUDE,
            "battery": int(battery),
            "status": "active",
        },
    )
    response.raise_for_status()


def _distance_meters(a: tuple[float, float], b: tuple[float, float]) -> float:
    lat_scale = 111_320.0
    mean_lat = math.radians((a[0] + b[0]) / 2)
    north = (a[0] - b[0]) * lat_scale
    east = (a[1] - b[1]) * lat_scale * math.cos(mean_lat)
    return math.hypot(north, east)


def _banner(message: str) -> None:
    line = "=" * (len(message) + 4)
    print(f"{line}\n  {message}\n{line}")


if __name__ == "__main__":
    import sys

    sys.stdout.reconfigure(line_buffering=True)
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        print("\n시나리오 종료.")
