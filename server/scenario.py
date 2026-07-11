"""
강남역 → 신논현역 6번 출구 재난 구조 시나리오
================================================
Usage:
    python3 scenario.py

환경변수:
    DRONE_SERVER_URL   서버 주소 (기본: http://localhost:8001)
    VOIP_HOST          VoIP 서버 호스트 (기본: localhost)
"""

from __future__ import annotations

import asyncio
import base64
import math
import os
import socket
import struct
import subprocess
import uuid
import zlib
from pathlib import Path

import httpx

SERVER_URL = os.environ.get("DRONE_SERVER_URL", "http://localhost:8001")
VOIP_HOST  = os.environ.get("VOIP_HOST", "localhost")
VOIP_PORT  = 5005

# 영상 프레임 시뮬레이션 (단색 PNG, 카메라 하드웨어 없이 파이프라인 검증용)
VIDEO_WIDTH, VIDEO_HEIGHT = 160, 120
VIDEO_COLORS = [(220, 40, 40), (40, 180, 80), (40, 100, 220), (230, 200, 40)]

# 격자 범위 (서버 config와 동일하게 맞춤)
GRID_LAT_MIN, GRID_LAT_MAX = 37.490, 37.515
GRID_LNG_MIN, GRID_LNG_MAX = 127.020, 127.040

# 강남역 (출발)
START_LAT = 37.4979
START_LNG = 127.0276

# 신논현역 6번 출구 (목표)
TARGET_LAT = 37.5044
TARGET_LNG = 127.0248

DRONE_ID   = 1
STEPS      = 30          # 이동 단계 수 (~30초)
ALTITUDE   = 50.0

TTS_SCRIPT = "살려주세요. 신논현역 6번 출구입니다. 빨리 와주세요."

SAMPLE_RATE = 16000
FRAME_BYTES = 640        # 20 ms × 16 kHz × 2 byte = 640 bytes/frame


# ---------------------------------------------------------------------------

async def run() -> None:
    async with httpx.AsyncClient(base_url=SERVER_URL, timeout=5.0) as client:
        _banner("재난 대응 드론 시나리오 시작")
        print(f"  출발지 : 강남역          ({START_LAT}, {START_LNG})")
        print(f"  목적지 : 신논현역 6번 출구 ({TARGET_LAT}, {TARGET_LNG})")
        print()

        # ── Phase 1: 강남역에서 출발 ──────────────────────────────────────
        await _telemetry(client, START_LAT, START_LNG, 100)
        await _signal(client, -40.0)
        print("[출발] 강남역 — 드론 이륙")
        await asyncio.sleep(1)

        # ── Phase 2: 신논현역 6번 출구로 이동 ────────────────────────────
        for step in range(1, STEPS + 1):
            t   = step / STEPS
            lat = START_LAT + (TARGET_LAT - START_LAT) * t
            lng = START_LNG + (TARGET_LNG - START_LNG) * t
            bat = 100 - step * 0.25

            # 목표에 가까울수록 RSS 강해짐
            dist    = math.hypot(lat - TARGET_LAT, lng - TARGET_LNG)
            rss_dbm = max(-100.0, min(-40.0, -40.0 - dist * 3000))

            await _telemetry(client, lat, lng, bat)
            await _signal(client, rss_dbm)

            bar = "█" * int(t * 25) + "░" * (25 - int(t * 25))
            print(f"[{step:02d}/{STEPS}] {bar}  RSS {rss_dbm:6.1f} dBm  bat {int(bat)}%")
            await asyncio.sleep(1)

        # ── Phase 3: 탐지 이벤트 ─────────────────────────────────────────
        print()
        _banner("요구조자 탐지 — 신논현역 6번 출구")
        resp = await _detection(client)
        voip_id = resp["voip_session_id"]
        print(f"VoIP 세션 ID : {voip_id}")
        print()

        # 탐지 직후에도 드론은 현장 호버링
        await _telemetry(client, TARGET_LAT, TARGET_LNG, 100 - STEPS * 0.25)

        # ── Phase 4: receiver 자동 기동 + TTS 준비 ───────────────────────
        pcm_data = _generate_tts(TTS_SCRIPT)   # 미리 생성 (1~2초 소요)

        receiver = _start_receiver(voip_id)     # Python receiver 기동
        print("VoIP 수신기 기동 — 2초 후 음성 전송...")
        for i in range(2):
            await _telemetry(client, TARGET_LAT, TARGET_LNG, 100 - STEPS * 0.25)
            await _video_frame(client, i)  # 탐지 시점부터 영상 프리뷰 채워지기 시작
            await asyncio.sleep(1)

        # ── Phase 5: UDP 전송 ─────────────────────────────────────────────
        await _send_audio(pcm_data, voip_id)
        receiver.wait()                         # 재생 완료 대기

        # ── Phase 6: 계속 호버링 ─────────────────────────────────────────
        print("\n드론 현장 호버링 중 (Ctrl+C로 종료)\n")
        tick = 0
        while True:
            bat = max(10, 100 - STEPS * 0.25 - tick * 0.1)
            await _telemetry(client, TARGET_LAT, TARGET_LNG, bat)
            await _video_frame(client, tick + 2)  # Phase 4의 seq(0,1) 다음부터 이어감
            tick += 1
            await asyncio.sleep(2)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

async def _video_frame(client: httpx.AsyncClient, seq: int) -> None:
    color = VIDEO_COLORS[seq % len(VIDEO_COLORS)]
    frame_b64 = base64.b64encode(_png_bytes(VIDEO_WIDTH, VIDEO_HEIGHT, color)).decode("ascii")
    await client.post(f"/drones/{DRONE_ID}/video", json={"frame_b64": frame_b64, "seq": seq})


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


async def _telemetry(client: httpx.AsyncClient, lat: float, lng: float, bat: float) -> None:
    await client.post(f"/drones/{DRONE_ID}/telemetry", json={
        "lat":      round(lat, 6),
        "lng":      round(lng, 6),
        "altitude": ALTITUDE,
        "battery":  int(bat),
        "status":   "active",
    })


async def _signal(client: httpx.AsyncClient, rss_dbm: float) -> None:
    await client.post(f"/drones/{DRONE_ID}/signal", json={
        "rss_dbm": round(rss_dbm, 1),
    })


async def _detection(client: httpx.AsyncClient) -> dict:
    row     = int((TARGET_LAT - GRID_LAT_MIN) / (GRID_LAT_MAX - GRID_LAT_MIN) * 10)
    col     = int((TARGET_LNG - GRID_LNG_MIN) / (GRID_LNG_MAX - GRID_LNG_MIN) * 10)
    cell_id = f"{chr(65 + min(row, 9))}{min(col, 9)}"
    r = await client.post("/detection", json={
        "drone_id":   DRONE_ID,
        "cell_id":    cell_id,
        "rss_dbm":    -41.5,
        "stream_url": None,
    })
    return r.json()


def _start_receiver(session_id: str) -> subprocess.Popen:
    env = {**os.environ, "DRONE_SERVER_URL": SERVER_URL, "VOIP_HOST": VOIP_HOST}
    return subprocess.Popen(
        ["python3", "-u", str(Path(__file__).parent / "receiver.py"), "--session", session_id],
        env=env,
    )


def _generate_tts(text: str) -> bytes:
    aiff = "/tmp/survivor.aiff"
    pcm  = "/tmp/survivor.pcm"
    print(f"TTS 생성 중 : \"{text}\"")
    subprocess.run(["say", "-v", "Yuna", "-o", aiff, text], check=True)
    subprocess.run([
        "ffmpeg", "-y", "-i", aiff,
        "-f", "s16le", "-acodec", "pcm_s16le",
        "-ar", str(SAMPLE_RATE), "-ac", "1", pcm,
    ], capture_output=True, check=True)
    data = open(pcm, "rb").read()
    print(f"PCM 생성 완료 : {len(data):,} bytes ({len(data) // FRAME_BYTES} frames)")
    return data


async def _send_audio(pcm_data: bytes, session_id: str) -> None:
    sid    = uuid.UUID(session_id)
    header = struct.Struct("!16sBL")
    sock   = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)

    print(f"UDP 음성 전송 → {VOIP_HOST}:{VOIP_PORT}")
    seq, offset = 0, 0
    while offset < len(pcm_data):
        chunk = pcm_data[offset : offset + FRAME_BYTES]
        if len(chunk) < FRAME_BYTES:
            chunk = chunk + b"\x00" * (FRAME_BYTES - len(chunk))
        packet = header.pack(sid.bytes, 0, seq) + chunk  # role=0 (SURVIVOR)
        sock.sendto(packet, (VOIP_HOST, VOIP_PORT))
        seq    += 1
        offset += FRAME_BYTES
        await asyncio.sleep(0.02)

    sock.close()
    print("음성 전송 완료")


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
