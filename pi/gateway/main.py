import math
import random
import time
from collections.abc import Iterator
from typing import Optional

from client import GatewayClient, extract_drone_id
from config import settings
from packet_parser import PacketParseError, parse_packet

# Gangnam Station -> Sinnonhyeon Station exit 6 — same coordinates/RSS
# formula as scenario.py, for a consistent demo scenario.
_START_LAT, _START_LNG = 37.4979, 127.0276
_TARGET_LAT, _TARGET_LNG = 37.5044, 127.0248
_APPROACH_STEPS = 30


def _build_packet(latitude: float, longitude: float, rssi: int, battery: int) -> str:
    return (
        f"drone-01,"
        f"{rssi},"
        f"{latitude:.6f},"
        f"{longitude:.6f},"
        f"{battery}"
    )


def generate_mock_packets() -> Iterator[str]:
    """Replay the same Gangnam -> Sinnonhyeon approach as scenario.py so it
    works without real hardware. RSS strengthens on approach, which lets
    DETECTION_MODE=rss_threshold actually fire; hovers in place after arrival."""

    battery = 100.0

    for step in range(1, _APPROACH_STEPS + 1):
        t = step / _APPROACH_STEPS
        latitude = _START_LAT + (_TARGET_LAT - _START_LAT) * t
        longitude = _START_LNG + (_TARGET_LNG - _START_LNG) * t
        battery = max(10.0, battery - 0.25)

        dist = math.hypot(latitude - _TARGET_LAT, longitude - _TARGET_LNG)
        rssi = int(max(-100.0, min(-40.0, -40.0 - dist * 3000)))

        yield _build_packet(latitude, longitude, rssi, int(battery))
        time.sleep(settings.send_interval)

    while True:
        battery = max(10.0, battery - 0.05)
        rssi = -40 + random.randint(-3, 0)
        yield _build_packet(_TARGET_LAT, _TARGET_LNG, rssi, int(battery))
        time.sleep(settings.send_interval)

def _read_serial_lines() -> Iterator[str]:
    """Read UART lines. If the connection drops (drone vibration, loose
    cable), keep retrying instead of killing the process."""
    try:
        import serial

    except ImportError as error:
        raise RuntimeError(
            "pyserial is not installed. Run 'pip install pyserial'."
        ) from error

    while True:
        try:
            print(
                f"[UART connecting] port={settings.serial_port}, "
                f"baud={settings.baud_rate}"
            )

            with serial.Serial(
                port=settings.serial_port,
                baudrate=settings.baud_rate,
                timeout=1
            ) as serial_connection:
                print("[UART connected]")

                while True:
                    raw_data = serial_connection.readline()

                    if not raw_data:
                        continue

                    try:
                        decoded_data = raw_data.decode(
                            "utf-8",
                            errors="strict"
                        ).strip()

                    except UnicodeDecodeError:
                        print("[decode error] data is not valid UTF-8.")
                        continue

                    if decoded_data:
                        yield decoded_data

        except KeyboardInterrupt:
            raise

        except serial.SerialException as error:
            print(
                f"[UART disconnected] {error} — "
                f"retrying in {settings.serial_reconnect_delay_sec}s"
            )
            time.sleep(settings.serial_reconnect_delay_sec)


def read_serial_packets() -> Iterator[str]:
    """Read one packet per line from the Raspberry Pi's USB UART/serial port."""
    return _read_serial_lines()


def run_raw_debug() -> None:
    """Print raw serial lines without parsing or sending — lets you check
    whether real hardware matches the format packet_parser.py assumes
    (5-field CSV) before wiring up the rest."""
    print("[debug mode] printing raw packets only, not sending to server.")
    for raw_data in _read_serial_lines():
        print(f"[raw] {raw_data!r}")


def get_packet_source() -> Iterator[str]:
    """Pick mock or UART input based on settings."""

    mode = settings.input_mode.lower()

    if mode == "mock":
        print("[input mode] mock test data")
        return generate_mock_packets()

    if mode == "serial":
        print("[input mode] UART serial data")
        return read_serial_packets()

    raise ValueError(
        f"Unsupported INPUT_MODE: {settings.input_mode}"
    )


def check_fpga_detection() -> Optional[tuple[int, float]]:
    """The original design has the FPGA fire a hardware interrupt when it
    identifies a survivor signal (see server/routers/detection.py). Whether
    that arrives as a special UART packet, a GPIO interrupt, or something
    else is not settled with the FPGA side yet, so this is just a placeholder.

    Once the FPGA interface is defined, read that signal here and return
    (drone_id, rss_dbm).
    """
    return None


def _try_send_detection(client: GatewayClient, drone_id: int, cell_id: Optional[str], rss_dbm: float) -> None:
    """Skip sending if cell_id is missing (outside the grid) — the server
    would reject it with 422 anyway, so don't waste retries on it."""
    if cell_id is None:
        print(
            f"[detection skipped] drone={drone_id} rss={rss_dbm}dBm — "
            "outside grid, no cell_id, skipping /detection"
        )
        return

    print(f"[detected] drone={drone_id} rss={rss_dbm}dBm cell={cell_id}")
    client.send_detection(drone_id, cell_id, rss_dbm)


class RssThresholdDetector:
    """RSS-threshold detection — a fallback until the FPGA path is ready.

    Won't re-trigger for the same drone until the cooldown elapses.
    """

    def __init__(self, threshold: float, cooldown_sec: float) -> None:
        self.threshold = threshold
        self.cooldown_sec = cooldown_sec
        self._last_triggered: dict[int, float] = {}

    def check(self, drone_id: int, rss_dbm: float) -> bool:
        if rss_dbm < self.threshold:
            return False

        last = self._last_triggered.get(drone_id, 0.0)
        if time.time() - last < self.cooldown_sec:
            return False

        self._last_triggered[drone_id] = time.time()
        return True


def main() -> None:
    print("=" * 50)
    print("Raspberry Pi Drone Gateway starting")
    print("=" * 50)

    print(f"Gateway ID     : {settings.gateway_id}")
    print(f"Input Mode     : {settings.input_mode}")
    print(f"Server URL     : {settings.server_url}")
    print(f"Detection Mode : {settings.detection_mode}")
    print(f"Dry Run        : {settings.dry_run}")
    print("=" * 50)

    if settings.input_mode.lower() == "raw_debug":
        try:
            run_raw_debug()
        except KeyboardInterrupt:
            print("\n[stopped] interrupted by user.")
        except Exception as error:
            print(f"\n[fatal error] {error}")
        return

    client = GatewayClient(
        server_url=settings.server_url,
        gateway_id=settings.gateway_id,
        timeout=settings.request_timeout,
        max_retries=settings.max_retries,
        dry_run=settings.dry_run
    )

    rss_detector = RssThresholdDetector(
        threshold=settings.rss_detection_threshold,
        cooldown_sec=settings.detection_cooldown_sec,
    )

    try:
        packet_source = get_packet_source()

        for raw_packet in packet_source:
            print(f"\n[raw packet] {raw_packet}")

            try:
                telemetry = parse_packet(raw_packet)

            except PacketParseError as error:
                print(f"[packet error] {error}")
                continue

            print(f"[parsed] {telemetry}")

            response = client.send_telemetry(telemetry)
            if response is None:
                continue

            drone_id = extract_drone_id(telemetry["drone_id"])
            cell_id = response.get("cell_id")
            rssi = telemetry["rssi"]

            client.send_signal(drone_id, rssi)

            if settings.detection_mode.lower() == "rss_threshold":
                if rss_detector.check(drone_id, rssi):
                    _try_send_detection(client, drone_id, cell_id, rssi)
            else:
                detected = check_fpga_detection()
                if detected is not None:
                    fpga_drone_id, fpga_rss = detected
                    _try_send_detection(client, fpga_drone_id, cell_id, fpga_rss)

    except KeyboardInterrupt:
        print("\n[stopped] interrupted by user.")

    except Exception as error:
        print(f"\n[fatal error] {error}")

    finally:
        client.close()
        print("[stopped] gateway connections closed.")


if __name__ == "__main__":
    main()
