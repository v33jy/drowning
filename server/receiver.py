"""
VoIP 수신기 — CONTROL 역할로 릴레이에 등록하고 survivor 음성을 실시간 재생.

Usage:
    python3 receiver.py

환경변수:
    DRONE_SERVER_URL   서버 주소 (기본: http://localhost:8001)
    VOIP_HOST          VoIP UDP 서버 (기본: localhost)
"""

from __future__ import annotations

import os
import socket
import struct
import subprocess
import time
import uuid

import httpx

SERVER_URL = os.environ.get("DRONE_SERVER_URL", "http://localhost:8001")
VOIP_HOST  = os.environ.get("VOIP_HOST", "localhost")
VOIP_PORT  = 5005

ROLE_CONTROL = 1
HEADER       = struct.Struct("!16sBL")   # uuid(16) + role(1) + seq(4) = 21 bytes
HEADER_SIZE  = HEADER.size               # 21


def wait_for_session(target_id: str | None = None) -> str:
    """VoIP 세션이 생성될 때까지 폴링. target_id가 주어지면 해당 세션만 기다림."""
    if target_id:
        print(f"세션 대기 중 : {target_id}", flush=True)
    else:
        print("탐지 이벤트 대기 중...", flush=True)
    while True:
        try:
            r = httpx.get(f"{SERVER_URL}/voip/sessions", timeout=3.0)
            active = [s for s in r.json() if s["active"]]
            if target_id:
                match = [s for s in active if s["session_id"] == target_id]
                if match:
                    return match[0]["session_id"]
            elif active:
                return active[0]["session_id"]
        except Exception:
            pass
        time.sleep(0.3)


def run(target_id: str | None = None) -> None:
    session_id = wait_for_session(target_id)
    print(f"VoIP 세션 감지 : {session_id}", flush=True)

    sid = uuid.UUID(session_id)

    # UDP 소켓 바인딩 (임의 포트)
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.bind(("0.0.0.0", 0))
    sock.settimeout(0.05)

    # 릴레이에 CONTROL로 등록 — 빈 패킷 한 개면 충분
    reg = HEADER.pack(sid.bytes, ROLE_CONTROL, 0) + b"\x00" * 640
    sock.sendto(reg, (VOIP_HOST, VOIP_PORT))
    print("릴레이 CONTROL 등록 완료", flush=True)
    print("요구조자 음성 대기 중...", flush=True)

    # ffplay는 첫 오디오 패킷 수신 후 lazy-start (프로브 타임아웃 방지)
    player: subprocess.Popen | None = None
    frames_received = 0
    try:
        while True:
            try:
                data, _ = sock.recvfrom(4096)
                if len(data) > HEADER_SIZE:
                    pcm = data[HEADER_SIZE:]
                    if player is None:
                        player = subprocess.Popen(
                            [
                                "ffplay",
                                "-f", "s16le",
                                "-ar", "16000",
                                "-ac", "1",
                                "-nodisp",
                                "-fflags", "nobuffer",
                                "-loglevel", "quiet",
                                "-",
                            ],
                            stdin=subprocess.PIPE,
                        )
                        print("▶ 음성 재생 시작", flush=True)
                    player.stdin.write(pcm)
                    player.stdin.flush()
                    frames_received += 1
            except socket.timeout:
                # 음성이 끝난 후 2초 침묵이면 종료
                if frames_received > 0:
                    break
            except BrokenPipeError:
                break
    except KeyboardInterrupt:
        pass
    finally:
        sock.close()
        if player:
            try:
                player.stdin.close()
            except Exception:
                pass
            player.wait()
        print(f"\n수신 완료 ({frames_received} frames). 종료.", flush=True)


if __name__ == "__main__":
    import argparse
    parser = argparse.ArgumentParser()
    parser.add_argument("--session", default=None, help="VoIP session UUID to join")
    args = parser.parse_args()
    run(target_id=args.session)
