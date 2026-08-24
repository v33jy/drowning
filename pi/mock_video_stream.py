"""테스트 패턴을 H.264로 인코딩해 MediaMTX RTSP 입력으로 송출한다."""

from __future__ import annotations

import argparse
import subprocess


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--url", default="rtsp://127.0.0.1:8554/drone")
    parser.add_argument("--width", type=int, default=854)
    parser.add_argument("--height", type=int, default=480)
    parser.add_argument("--fps", type=int, default=10)
    parser.add_argument("--bitrate", default="800k")
    args = parser.parse_args()

    subprocess.run(
        [
            "ffmpeg",
            "-re",
            "-f",
            "lavfi",
            "-i",
            f"testsrc2=size={args.width}x{args.height}:rate={args.fps}",
            "-an",
            "-c:v",
            "libx264",
            "-preset",
            "veryfast",
            "-tune",
            "zerolatency",
            "-b:v",
            args.bitrate,
            "-pix_fmt",
            "yuv420p",
            "-f",
            "rtsp",
            "-rtsp_transport",
            "tcp",
            args.url,
        ],
        check=True,
    )


if __name__ == "__main__":
    main()
