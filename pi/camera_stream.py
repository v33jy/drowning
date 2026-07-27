"""
Camera streamer — captures frames from a CSI camera module (IMX219 etc, via
picamera2) and streams them to the server's video WebSocket endpoint
(/drones/{id}/video).

Usage (on the Raspberry Pi):
    python3 camera_stream.py --drone-id 1 --fps 12
    python3 camera_stream.py --sharpness 2.0 --exposure-time 8000 --unsharp 0.6

To verify the rest of the pipeline (server connection, sending, app display)
without a camera/Raspberry Pi, add --mock (picamera2 isn't imported at all
in this mode, so it also runs on a regular dev machine):
    python3 camera_stream.py --mock --drone-id 1

Env vars:
    DRONE_SERVER_URL   Server address (default: http://localhost:8001)

Requirements:
    pip install picamera2 opencv-python-headless websockets
    (picamera2 is usually preinstalled on Raspberry Pi OS; not needed for --mock)

Note:
    The server only accepts this connection after drone_id has already sent
    telemetry (server/routers/video.py) — start the flight-controller script
    first.
"""

from __future__ import annotations

import argparse
import os
import time
from typing import Optional

import cv2
import numpy as np
from websockets.sync.client import connect

SERVER_URL = os.environ.get("DRONE_SERVER_URL", "http://localhost:8001")
WS_URL = SERVER_URL.replace("http://", "ws://").replace("https://", "wss://")


class MockCamera:
    """Generates synthetic frames instead of a real camera/picamera2. Only
    the capture step is faked — encoding and sending stay identical to the
    real path, so the rest of the pipeline can be verified without hardware.
    Frames are labeled "MOCK CAM" so they're never mistaken for real footage."""

    _COLORS = [(220, 40, 40), (40, 180, 80), (40, 100, 220), (230, 200, 40)]

    def __init__(self, width: int, height: int, fps: int) -> None:
        self._width = width
        self._height = height
        self._fps = fps
        self._frame_count = 0

    def capture_array(self) -> np.ndarray:
        color = self._COLORS[(self._frame_count // max(1, self._fps)) % len(self._COLORS)]
        frame = np.full((self._height, self._width, 3), color, dtype=np.uint8)
        cv2.putText(
            frame, f"MOCK CAM  frame {self._frame_count}",
            (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (255, 255, 255), 2,
        )
        self._frame_count += 1
        return frame

    def stop(self) -> None:
        pass


def _init_real_camera(width: int, height: int, sharpness: float, exposure_time: Optional[int]):
    """Initialize the real camera. Retries instead of crashing if it's not
    detected yet at boot or the cable connection is momentarily bad (drone
    vibration)."""
    from picamera2 import Picamera2

    while True:
        try:
            cam = Picamera2()
            cam.configure(cam.create_video_configuration(main={"size": (width, height), "format": "RGB888"}))
            cam.start()
            _apply_controls(cam, sharpness, exposure_time)
            return cam
        except KeyboardInterrupt:
            raise
        except Exception as exc:
            print(f"[카메라 초기화 실패] {exc} — 3초 후 재시도", flush=True)
            time.sleep(3)


def _apply_controls(cam, sharpness: float, exposure_time: Optional[int]) -> None:
    """The cheap fixed-focus lens can't be fully de-blurred, but a short
    fixed exposure cuts motion blur in flight, and a higher Sharpness makes
    edges read more clearly to a human viewer. exposure_time needs tuning
    for actual lighting, so auto-exposure is left alone unless it's set."""
    controls: dict = {"Sharpness": sharpness}
    if exposure_time is not None:
        controls["AeEnable"] = False
        controls["ExposureTime"] = exposure_time
    cam.set_controls(controls)


def _unsharp_mask(frame: np.ndarray, amount: float) -> np.ndarray:
    """Boost edge contrast by adding back a scaled Gaussian-blur difference.
    Doesn't recover detail lost to defocus, but reads as less blurry to a
    human viewer."""
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
    mock: bool,
) -> None:
    if mock:
        cam = MockCamera(width, height, fps)
        print(f"[MOCK 모드] 합성 프레임 사용 ({width}x{height} @ {fps}fps)", flush=True)
    else:
        cam = _init_real_camera(width, height, sharpness, exposure_time)
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
    parser.add_argument("--mock", action="store_true", help="picamera2/실제 카메라 없이 합성 프레임으로 나머지 파이프라인만 검증")
    args = parser.parse_args()
    run(
        args.drone_id, args.width, args.height, args.fps, args.quality,
        args.sharpness, args.exposure_time, args.unsharp, args.mock,
    )
