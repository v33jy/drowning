"""
카메라 스트리머 — CSI 카메라 모듈(IMX219 등, picamera2)로 촬영한 프레임을
서버의 영상 WebSocket 엔드포인트(/drones/{id}/video)로 계속 스트리밍.

Usage (라즈베리파이 위에서):
    python3 camera_stream.py --drone-id 1 --fps 12
    python3 camera_stream.py --sharpness 2.0 --exposure-time 8000 --unsharp 0.6

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
from typing import Optional

import cv2
import numpy as np
from picamera2 import Picamera2
from websockets.sync.client import connect

SERVER_URL = os.environ.get("DRONE_SERVER_URL", "http://localhost:8001")
WS_URL = SERVER_URL.replace("http://", "ws://").replace("https://", "wss://")


def _apply_controls(cam: Picamera2, sharpness: float, exposure_time: Optional[int]) -> None:
    """저가 고정초점 렌즈라 흐릿하게 잡히는 걸 완전히 못 없애지만, 노출을 짧게
    고정하면 비행 중 모션블러가 줄고 Sharpness를 올리면 사람 눈에는 윤곽이 더
    또렷해 보인다. exposure_time은 실제 조도에 따라 튜닝이 필요해서 값을 안
    주면 자동노출(카메라 기본값)을 그대로 둔다."""
    controls: dict = {"Sharpness": sharpness}
    if exposure_time is not None:
        controls["AeEnable"] = False
        controls["ExposureTime"] = exposure_time
    cam.set_controls(controls)


def _unsharp_mask(frame: np.ndarray, amount: float) -> np.ndarray:
    """가우시안 블러를 뺀 만큼 원본에 더해 엣지 대비를 강조한다. 아웃포커스로
    날아간 디테일을 복원하진 못하지만, 사람이 보기엔 덜 흐릿하게 보인다."""
    blurred = cv2.GaussianBlur(frame, (0, 0), sigmaX=2)
    return cv2.addWeighted(frame, 1 + amount, blurred, -amount, 0)


def run(
    drone_id: int,
    width: int,
    height: int,
    fps: int,
    quality: int,
    sharpness: float,
    exposure_time: Optional[int],
    unsharp: float,
) -> None:
    cam = Picamera2()
    cam.configure(cam.create_video_configuration(main={"size": (width, height), "format": "RGB888"}))
    cam.start()
    _apply_controls(cam, sharpness, exposure_time)
    print(f"카메라 시작 ({width}x{height} @ {fps}fps, sharpness={sharpness}, exposure_time={exposure_time})", flush=True)

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
                        if unsharp > 0:
                            frame = _unsharp_mask(frame, unsharp)
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
    parser.add_argument("--sharpness", type=float, default=1.0, help="libcamera Sharpness 컨트롤 (기본값 1.0 = 카메라 기본)")
    parser.add_argument("--exposure-time", type=int, default=None, help="수동 노출 시간(마이크로초). 안 주면 자동노출 유지 — 실제 조도 보고 튜닝 필요")
    parser.add_argument("--unsharp", type=float, default=0.0, help="후처리 언샤프 마스크 강도 (0=끔)")
    args = parser.parse_args()
    run(
        args.drone_id, args.width, args.height, args.fps, args.quality,
        args.sharpness, args.exposure_time, args.unsharp,
    )
