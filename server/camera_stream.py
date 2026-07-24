"""
카메라 스트리머 — CSI 카메라 모듈(IMX219 등, picamera2)로 촬영한 프레임을
서버의 영상 WebSocket 엔드포인트(/drones/{id}/video)로 계속 스트리밍.

Usage (라즈베리파이 위에서):
    python3 camera_stream.py --drone-id 1 --fps 12

환경변수:
    DRONE_SERVER_URL   서버 주소 (기본: http://localhost:8001)

요구사항:
    pip install picamera2 opencv-python-headless websockets
    (picamera2는 라즈베리파이 OS에 보통 이미 설치돼 있음)

참고:
    서버는 해당 drone_id가 텔레메트리를 먼저 보낸 적이 있어야 이 연결을
    받아준다 (server/routers/video.py). 텔레메트리를 보내는 비행 컨트롤러
    쪽 스크립트를 먼저 켜둘 것.
"""

from __future__ import annotations

import argparse
import os
import time

import cv2
from picamera2 import Picamera2
from websockets.sync.client import connect

SERVER_URL = os.environ.get("DRONE_SERVER_URL", "http://localhost:8001")
WS_URL = SERVER_URL.replace("http://", "ws://").replace("https://", "wss://")


def run(drone_id: int, width: int, height: int, fps: int, quality: int) -> None:
    cam = Picamera2()
    cam.configure(cam.create_video_configuration(main={"size": (width, height), "format": "RGB888"}))
    cam.start()
    print(f"카메라 시작 ({width}x{height} @ {fps}fps)", flush=True)

    url = f"{WS_URL}/drones/{drone_id}/video"
    interval = 1 / fps

    try:
        while True:
            try:
                print(f"서버 연결 중 : {url}", flush=True)
                with connect(url) as ws:
                    print("연결됨 — 스트리밍 시작", flush=True)
                    while True:
                        t0 = time.monotonic()
                        frame = cam.capture_array()
                        ok, jpeg = cv2.imencode(".jpg", frame, [cv2.IMWRITE_JPEG_QUALITY, quality])
                        if ok:
                            ws.send(jpeg.tobytes())
                        elapsed = time.monotonic() - t0
                        time.sleep(max(0.0, interval - elapsed))
            except KeyboardInterrupt:
                raise
            except Exception as exc:
                print(f"연결 끊김 ({exc}) — 1초 후 재연결", flush=True)
                time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        cam.stop()
        print("\n스트리밍 종료.", flush=True)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--drone-id", type=int, default=1)
    parser.add_argument("--width", type=int, default=1280)
    parser.add_argument("--height", type=int, default=720)
    parser.add_argument("--fps", type=int, default=12)
    parser.add_argument("--quality", type=int, default=70, help="JPEG 품질 (1-100)")
    args = parser.parse_args()
    run(args.drone_id, args.width, args.height, args.fps, args.quality)
