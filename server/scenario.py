"""
강남역 → 신논현역 6번 출구 재난 구조 시나리오
================================================
Usage:
    python3 scenario.py

환경변수:
    DRONE_SERVER_URL   서버 주소 (기본: http://localhost:8001)
"""

from __future__ import annotations

import asyncio
import math
import os
import struct
import zlib

import httpx
import websockets

SERVER_URL = os.environ.get("DRONE_SERVER_URL", "http://localhost:8001")
WS_URL     = SERVER_URL.replace("http://", "ws://").replace("https://", "wss://")

# 영상 프레임 시뮬레이션 (단색 PNG, 카메라 하드웨어 없이 파이프라인 검증용)
VIDEO_WIDTH, VIDEO_HEIGHT = 160, 120
VIDEO_COLORS = [(220, 40, 40), (40, 180, 80), (40, 100, 220), (230, 200, 40)]
VIDEO_FPS = 10

# 강남역 (출발)
START_LAT = 37.4979
START_LNG = 127.0276

# 신논현역 6번 출구 (목표)
TARGET_LAT = 37.5044
TARGET_LNG = 127.0248

DRONE_ID   = int(os.environ.get("DRONE_ID", "1"))
STEPS      = 30          # 이동 단계 수
STEP_INTERVAL = 0.3      # 단계당 대기 시간(초) — 총 이동 시간 ~STEPS*STEP_INTERVAL초
ALTITUDE   = 50.0


# ---------------------------------------------------------------------------

async def run() -> None:
    async with httpx.AsyncClient(base_url=SERVER_URL, timeout=5.0) as client:
        _banner("재난 대응 드론 시나리오 시작")
        print(f"  출발지 : 강남역          ({START_LAT}, {START_LNG})")
        print(f"  목적지 : 신논현역 6번 출구 ({TARGET_LAT}, {TARGET_LNG})")
        print()

        # ── Phase 1: 강남역에서 출발 ──────────────────────────────────────
        cell_id = await _telemetry(client, START_LAT, START_LNG, 100)
        await _signal(client, -40.0)
        print("[출발] 강남역 — 드론 이륙")
        await asyncio.sleep(STEP_INTERVAL)

        # ── Phase 2: 신논현역 6번 출구로 이동 ────────────────────────────
        for step in range(1, STEPS + 1):
            t   = step / STEPS
            lat = START_LAT + (TARGET_LAT - START_LAT) * t
            lng = START_LNG + (TARGET_LNG - START_LNG) * t
            bat = 100 - step * 0.25

            # 목표에 가까울수록 RSS 강해짐
            dist    = math.hypot(lat - TARGET_LAT, lng - TARGET_LNG)
            rss_dbm = max(-100.0, min(-40.0, -40.0 - dist * 3000))

            cell_id = await _telemetry(client, lat, lng, bat)
            await _signal(client, rss_dbm)

            bar = "█" * int(t * 25) + "░" * (25 - int(t * 25))
            print(f"[{step:02d}/{STEPS}] {bar}  RSS {rss_dbm:6.1f} dBm  bat {int(bat)}%")
            await asyncio.sleep(STEP_INTERVAL)

        # ── Phase 3: 탐지 이벤트 ─────────────────────────────────────────
        print()
        _banner("요구조자 탐지 — 신논현역 6번 출구")
        resp = await _detection(client, cell_id)
        detection_id = resp["detection_id"]
        print(f"탐지 ID : {detection_id}")
        print()

        # 탐지 직후에도 드론은 현장 호버링
        await _telemetry(client, TARGET_LAT, TARGET_LNG, 100 - STEPS * 0.25)

        # 탐지 시점부터 영상은 별도 WebSocket 연결로 계속 스트리밍 (텔레메트리 주기와 무관)
        video_task = asyncio.create_task(_stream_video())

        try:
            # ── Phase 4: 계속 호버링 ───────────────────────────────────────
            print("\n드론 현장 호버링 중 (Ctrl+C로 종료)\n")
            tick = 0
            while True:
                bat = max(10, 100 - STEPS * 0.25 - tick * 0.1)
                await _telemetry(client, TARGET_LAT, TARGET_LNG, bat)
                tick += 1
                await asyncio.sleep(2)
        finally:
            video_task.cancel()


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _stream_video() -> None:
    """Open one WS connection and push frames continuously at VIDEO_FPS —
    this is what real streaming looks like, vs. the old POST-per-frame hack.
    Runs as a background task until cancelled; reconnects if the socket drops.
    """
    url = f"{WS_URL}/drones/{DRONE_ID}/video"
    seq = 0
    while True:
        try:
            async with websockets.connect(url) as ws:
                while True:
                    color = VIDEO_COLORS[(seq // VIDEO_FPS) % len(VIDEO_COLORS)]  # 1초에 한 번 색 전환
                    frame = _png_bytes(VIDEO_WIDTH, VIDEO_HEIGHT, color)
                    await ws.send(frame)
                    seq += 1
                    await asyncio.sleep(1 / VIDEO_FPS)
        except asyncio.CancelledError:
            raise
        except Exception:
            await asyncio.sleep(1)  # 서버 재시작 등으로 끊기면 잠시 후 재연결


def _png_bytes(width: int, height: int, rgb: tuple[int, int, int]) -> bytes:
    """Hand-build a minimal solid-color PNG — no Pillow dependency needed."""
    def chunk(tag: bytes, data: bytes) -> bytes:
        return struct.pack("!I", len(data)) + tag + data + struct.pack("!I", zlib.crc32(tag + data))

    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack("!IIBBBBB", width, height, 8, 2, 0, 0, 0)  # 8-bit, RGB, no interlace
    raw_row = b"\x00" + bytes(rgb) * width  # filter byte 0 (none) + RGB pixels
    raw = raw_row * height
    idat = zlib.compress(raw, 6)
    return sig + chunk(b"IHDR", ihdr) + chunk(b"IDAT", idat) + chunk(b"IEND", b"")


async def _telemetry(client: httpx.AsyncClient, lat: float, lng: float, bat: float) -> str | None:
    r = await client.post(f"/drones/{DRONE_ID}/telemetry", json={
        "lat":      round(lat, 6),
        "lng":      round(lng, 6),
        "altitude": ALTITUDE,
        "battery":  int(bat),
        "status":   "active",
    })
    return r.json().get("cell_id")


async def _signal(client: httpx.AsyncClient, rss_dbm: float) -> None:
    await client.post(f"/drones/{DRONE_ID}/signal", json={
        "rss_dbm": round(rss_dbm, 1),
    })


async def _detection(client: httpx.AsyncClient, cell_id: str | None) -> dict:
    r = await client.post("/detection", json={
        "drone_id":   DRONE_ID,
        "cell_id":    cell_id,
        "rss_dbm":    -41.5,
        "stream_url": None,
    })
    return r.json()


def _banner(msg: str) -> None:
    line = "=" * (len(msg) + 4)
    print(line)
    print(f"  {msg}")
    print(line)


if __name__ == "__main__":
    import sys
    # Unbuffered output so logs appear immediately when redirected.
    sys.stdout.reconfigure(line_buffering=True)
    try:
        asyncio.run(run())
    except KeyboardInterrupt:
        print("\n시나리오 종료.")
