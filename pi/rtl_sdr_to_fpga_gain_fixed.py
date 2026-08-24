#!/usr/bin/env python3
"""
RTL-SDR Blog V3 -> Raspberry Pi -> Basys 3 SPI I/Q bridge.

Default field-test RF plan:
  Ground ESP32 beacon : 915.000 MHz
  RTL-SDR center      : 914.750 MHz
  Sample rate         : 1.000 MS/s
  Beacon offset       : +250 kHz -> FFT bin 256 (1024-point FFT)

FPGA packet format (spi_iq_source.v):
  'IQF1' + seq(u32 LE) + sample_count(u32 LE) + target_bin(u16 LE)
  + detect_shift(u8) + flags(u8) + unsigned I/Q bytes.
"""

from __future__ import annotations

import argparse
import logging
import os
import signal
import struct
import subprocess
import sys
import threading
import time
from pathlib import Path

try:
    import spidev
except ImportError as exc:
    print("python3-spidev가 필요합니다: sudo apt install python3-spidev", file=sys.stderr)
    raise

FFT_SIZE = 1024
BYTES_PER_COMPLEX_SAMPLE = 2
FRAME_BYTES = FFT_SIZE * BYTES_PER_COMPLEX_SAMPLE
MAGIC = b"IQF1"

DEFAULT_BEACON_HZ = 915_000_000
DEFAULT_CENTER_HZ = 914_750_000
DEFAULT_SAMPLE_RATE = 1_000_000
DEFAULT_SPI_HZ = 20_000_000
DEFAULT_GAIN_DB = 28.0  # 거리 비교용 고정 gain 기본값; 필요하면 --gain-db로 변경
DEFAULT_DETECT_SHIFT = 1
DEFAULT_TARGET_BIN = 256
DEFAULT_FLAGS = 0x00  # bit0=0: target-band energy detector

shutdown_requested = False


def request_shutdown(signum, _frame):
    global shutdown_requested
    logging.info("종료 신호 수신: %s", signum)
    shutdown_requested = True


def read_exact(stream, size: int) -> bytes:
    data = bytearray()
    while len(data) < size and not shutdown_requested:
        chunk = stream.read(size - len(data))
        if not chunk:
            break
        data.extend(chunk)
    return bytes(data)


def stderr_pump(pipe):
    try:
        for raw in iter(pipe.readline, b""):
            line = raw.decode(errors="replace").strip()
            if line:
                logging.info("rtl_sdr: %s", line)
    except Exception:
        logging.exception("rtl_sdr stderr reader 오류")


def build_packet(sequence: int, iq_bytes: bytes, target_bin: int, detect_shift: int) -> bytes:
    if len(iq_bytes) != FRAME_BYTES:
        raise ValueError(f"I/Q frame must be {FRAME_BYTES} bytes")
    header = MAGIC + struct.pack(
        "<IIHBB",
        sequence & 0xFFFFFFFF,
        FFT_SIZE,
        target_bin,
        detect_shift,
        DEFAULT_FLAGS,
    )
    return header + iq_bytes


def start_rtl_sdr(device: int, center_hz: int, sample_rate: int, ppm: int, gain_db: float | None) -> subprocess.Popen:
    cmd = [
        "rtl_sdr",
        "-d", str(device),
        "-f", str(center_hz),
        "-s", str(sample_rate),
        "-p", str(ppm),
    ]

    # 거리별 magnitude를 비교할 때는 자동 gain을 쓰면 수신 증폭량이 바뀔 수 있으므로
    # 고정 gain을 사용합니다. --auto-gain을 주면 기존 자동 gain 방식으로 돌아갑니다.
    if gain_db is not None:
        cmd.extend(["-g", f"{gain_db:g}"])

    cmd.append("-")  # stdout
    logging.info("RTL-SDR 시작: %s", " ".join(cmd))
    proc = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        bufsize=0,
    )
    assert proc.stdout is not None
    assert proc.stderr is not None
    threading.Thread(target=stderr_pump, args=(proc.stderr,), daemon=True).start()
    return proc


def open_spi(bus: int, device: int, speed_hz: int):
    spi = spidev.SpiDev()
    spi.open(bus, device)
    spi.mode = 0
    spi.max_speed_hz = speed_hz
    spi.bits_per_word = 8
    spi.no_cs = False
    return spi


def run(args) -> int:
    expected_target = round((args.beacon_hz - args.center_hz) * FFT_SIZE / args.sample_rate) % FFT_SIZE
    if args.target_bin is None:
        target_bin = expected_target
    else:
        target_bin = args.target_bin

    if not (0 <= target_bin <= 1023):
        raise ValueError("target_bin must be 0..1023")
    if not (0 <= args.detect_shift <= 15):
        raise ValueError("detect_shift must be 0..15")
    if args.spi_hz > 20_000_000:
        raise ValueError("현재 FPGA spi_iq_source는 SPI 20 MHz 이하로 사용해야 합니다")

    gain_db = None if args.auto_gain else args.gain_db
    if gain_db is not None and gain_db <= 0:
        raise ValueError("고정 gain은 0보다 큰 dB 값이어야 합니다. 자동 gain은 --auto-gain을 사용하세요")

    gain_text = "AUTO" if gain_db is None else f"FIXED {gain_db:g} dB"
    logging.info(
        "설정: beacon=%.6fMHz center=%.6fMHz rate=%.3fMS/s target_bin=%d SPI=%.1fMHz shift=%d gain=%s",
        args.beacon_hz / 1e6,
        args.center_hz / 1e6,
        args.sample_rate / 1e6,
        target_bin,
        args.spi_hz / 1e6,
        args.detect_shift,
        gain_text,
    )

    spi = open_spi(args.spi_bus, args.spi_device, args.spi_hz)
    rtl = None
    sequence = 1
    frame_count = 0
    last_stat = time.monotonic()

    try:
        while not shutdown_requested:
            if rtl is None or rtl.poll() is not None:
                if rtl is not None:
                    logging.warning("rtl_sdr 종료 감지(code=%s). 2초 후 재시작", rtl.returncode)
                    time.sleep(2.0)
                rtl = start_rtl_sdr(
                    args.rtl_device,
                    args.center_hz,
                    args.sample_rate,
                    args.ppm,
                    gain_db,
                )
                time.sleep(0.3)

            assert rtl.stdout is not None
            iq = read_exact(rtl.stdout, FRAME_BYTES)
            if len(iq) != FRAME_BYTES:
                logging.warning("I/Q short read %d/%d", len(iq), FRAME_BYTES)
                try:
                    rtl.terminate()
                except Exception:
                    pass
                rtl = None
                continue

            packet = build_packet(sequence, iq, target_bin, args.detect_shift)

            # packet length = 2064 bytes; 일반 spidev 4096-byte 버퍼보다 작아 CS가 중간에 끊기지 않습니다.
            spi.xfer2(list(packet), args.spi_hz, 0, 8)

            frame_count += 1
            sequence = (sequence + 1) & 0xFFFFFFFF
            if sequence == 0:
                sequence = 1

            now = time.monotonic()
            if now - last_stat >= 5.0:
                fps = frame_count / (now - last_stat)
                logging.info("SPI 전송 정상: %.1f FFT frames/s", fps)
                frame_count = 0
                last_stat = now

    finally:
        try:
            spi.close()
        except Exception:
            pass
        if rtl is not None and rtl.poll() is None:
            rtl.terminate()
            try:
                rtl.wait(timeout=2)
            except subprocess.TimeoutExpired:
                rtl.kill()
    return 0


def parse_args():
    p = argparse.ArgumentParser()
    p.add_argument("--rtl-device", type=int, default=0)
    p.add_argument("--beacon-hz", type=int, default=DEFAULT_BEACON_HZ)
    p.add_argument("--center-hz", type=int, default=DEFAULT_CENTER_HZ)
    p.add_argument("--sample-rate", type=int, default=DEFAULT_SAMPLE_RATE)
    p.add_argument("--ppm", type=int, default=0)
    p.add_argument("--spi-bus", type=int, default=0)
    p.add_argument("--spi-device", type=int, default=0)
    p.add_argument("--spi-hz", type=int, default=DEFAULT_SPI_HZ)
    gain_group = p.add_mutually_exclusive_group()
    gain_group.add_argument(
        "--gain-db",
        type=float,
        default=DEFAULT_GAIN_DB,
        help=f"RTL-SDR 고정 tuner gain(dB). 기본값: {DEFAULT_GAIN_DB:g} dB",
    )
    gain_group.add_argument(
        "--auto-gain",
        action="store_true",
        help="RTL-SDR 자동 gain 사용(거리별 magnitude 비교 시에는 권장하지 않음)",
    )
    p.add_argument("--target-bin", type=int, default=None)
    p.add_argument("--detect-shift", type=int, default=DEFAULT_DETECT_SHIFT)
    p.add_argument("--log-file", default="")
    return p.parse_args()


def main():
    args = parse_args()
    handlers = [logging.StreamHandler(sys.stdout)]
    if args.log_file:
        Path(args.log_file).parent.mkdir(parents=True, exist_ok=True)
        handlers.append(logging.FileHandler(args.log_file))
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(message)s",
        handlers=handlers,
    )
    signal.signal(signal.SIGINT, request_shutdown)
    signal.signal(signal.SIGTERM, request_shutdown)
    return run(args)


if __name__ == "__main__":
    raise SystemExit(main())
