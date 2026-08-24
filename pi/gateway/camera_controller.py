from __future__ import annotations

import subprocess
import time
from dataclasses import dataclass
from typing import Protocol


class VideoPublisher(Protocol):
    @property
    def running(self) -> bool: ...

    def start(self) -> None: ...

    def stop(self) -> None: ...


@dataclass
class H264RtspPublisher:
    width: int
    height: int
    fps: int
    bitrate: int
    rtsp_url: str
    _camera: subprocess.Popen | None = None
    _relay: subprocess.Popen | None = None

    @classmethod
    def from_settings(cls, settings) -> "H264RtspPublisher":
        return cls(
            width=settings.camera_width,
            height=settings.camera_height,
            fps=settings.camera_fps,
            bitrate=settings.camera_bitrate,
            rtsp_url=settings.camera_rtsp_url,
        )

    @property
    def running(self) -> bool:
        return (
            self._camera is not None
            and self._camera.poll() is None
            and self._relay is not None
            and self._relay.poll() is None
        )

    def _camera_command(self) -> list[str]:
        return [
            "rpicam-vid",
            "--timeout", "0",
            "--width", str(self.width),
            "--height", str(self.height),
            "--framerate", str(self.fps),
            "--bitrate", str(self.bitrate),
            "--codec", "h264",
            "--inline",
            "--intra", str(self.fps),
            "--nopreview",
            "--output", "-",
        ]

    def _relay_command(self) -> list[str]:
        return [
            "ffmpeg",
            "-nostdin",
            "-loglevel", "warning",
            "-f", "h264",
            "-i", "pipe:0",
            "-c:v", "copy",
            "-f", "rtsp",
            "-rtsp_transport", "tcp",
            self.rtsp_url,
        ]

    def start(self) -> None:
        if self.running:
            return
        self.stop()
        self._camera = subprocess.Popen(
            self._camera_command(),
            stdout=subprocess.PIPE,
        )
        try:
            self._relay = subprocess.Popen(
                self._relay_command(),
                stdin=self._camera.stdout,
            )
            if self._camera.stdout is not None:
                self._camera.stdout.close()
        except Exception:
            self.stop()
            raise

    def stop(self) -> None:
        processes = tuple(
            process
            for process in (self._relay, self._camera)
            if process is not None
        )
        for process in processes:
            if process.poll() is None:
                process.terminate()
        for process in processes:
            self._wait_for_exit(process)
        self._relay = None
        self._camera = None

    @staticmethod
    def _wait_for_exit(process: subprocess.Popen) -> None:
        try:
            process.wait(timeout=3)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


class CameraController:
    def __init__(
        self,
        publisher: VideoPublisher,
        enabled: bool,
        hold_seconds: float,
    ) -> None:
        self.publisher = publisher
        self.enabled = enabled
        self.hold_seconds = max(0.0, hold_seconds)
        self._last_active_at: float | None = None

    def update(
        self,
        *,
        camera_arm: bool,
        detected: bool,
        now: float | None = None,
    ) -> None:
        if not self.enabled:
            return
        timestamp = time.monotonic() if now is None else now
        if camera_arm or detected:
            self._last_active_at = timestamp
            if not self.publisher.running:
                self.publisher.start()
            return
        if (
            self.publisher.running
            and self._last_active_at is not None
            and timestamp - self._last_active_at >= self.hold_seconds
        ):
            self.publisher.stop()
            self._last_active_at = None

    def close(self) -> None:
        self.publisher.stop()
