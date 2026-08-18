import math
import random
import time
from collections.abc import Iterator
from typing import Optional

from client import GatewayClient, extract_drone_id
from config import settings
from mavlink_telemetry import (
    MavlinkTelemetryService,
    combine_measurements,
)
from measurement import SignalMeasurement, SignalObservation
from signal_pipeline.factory import create_fpga_transport, create_sdr_source
from signal_pipeline.pipeline import SignalPipeline

# Gangnam Station -> Sinnonhyeon Station exit 6 — same coordinates/RSS
# formula as scenario.py, for a consistent demo scenario.
_START_LAT, _START_LNG = 37.4979, 127.0276
_TARGET_LAT, _TARGET_LNG = 37.5044, 127.0248
_APPROACH_STEPS = 30
_SIGNAL_PIPELINE_MODE = "signal_pipeline"


def _build_mock_observation(
    latitude: float,
    longitude: float,
    rssi: int,
    battery: int,
) -> SignalObservation:
    measured_at = time.time()
    return SignalObservation(
        drone_id=settings.drone_id,
        rss_dbm=float(rssi),
        latitude=latitude,
        longitude=longitude,
        altitude=0.0,
        battery=battery,
        signal_measured_at=measured_at,
        position_measured_at=measured_at,
    )


def generate_mock_observations() -> Iterator[SignalObservation]:
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

        yield _build_mock_observation(
            latitude,
            longitude,
            rssi,
            int(battery),
        )
        time.sleep(settings.send_interval)

    while True:
        battery = max(10.0, battery - 0.05)
        rssi = -40 + random.randint(-3, 0)
        yield _build_mock_observation(
            _TARGET_LAT,
            _TARGET_LNG,
            rssi,
            int(battery),
        )
        time.sleep(settings.send_interval)


def generate_signal_measurements() -> Iterator[SignalMeasurement]:
    """Generate RSS measurements from the configured SDR/FPGA pipeline."""
    pipeline = SignalPipeline(
        sdr_source=create_sdr_source(),
        fpga_transport=create_fpga_transport(),
    )
    try:
        while True:
            result = pipeline.process_next_frame()
            print(
                f"[SIGNAL] sequence={result.sequence} "
                f"peak_bin={result.peak_bin} rss={result.rss_dbm:.2f}dBm "
                f"detected={result.detected}"
            )

            yield SignalMeasurement(
                rss_dbm=result.rss_dbm,
                measured_at=time.time(),
            )
            time.sleep(settings.send_interval)
    finally:
        pipeline.close()


def get_measurement_source(
) -> Iterator[SignalMeasurement | SignalObservation]:
    """Pick the all-mock or real hardware telemetry source."""

    mode = settings.input_mode.lower()

    if mode == "mock":
        print("[input mode] mock test data")
        return generate_mock_observations()

    if mode == _SIGNAL_PIPELINE_MODE:
        print("[input mode] H743 MAVLink + SDR -> FPGA signal pipeline")
        return generate_signal_measurements()

    raise ValueError(
        f"Unsupported INPUT_MODE: {settings.input_mode}"
    )


def uses_rss_detection() -> bool:
    return (
        settings.detection_mode.lower() == "rss_threshold"
        or settings.input_mode.lower() == _SIGNAL_PIPELINE_MODE
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


def _try_send_detection(
    client: GatewayClient,
    drone_id: int,
    cell_id: Optional[str],
    rss_dbm: float
) -> None:
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
    print(
        "MAVLink        : "
        f"{settings.input_mode.lower() == _SIGNAL_PIPELINE_MODE}"
    )
    print(f"Dry Run        : {settings.dry_run}")
    print("=" * 50)

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

    measurement_source = None
    mavlink_service = None

    try:
        if settings.input_mode.lower() == _SIGNAL_PIPELINE_MODE:
            mavlink_service = MavlinkTelemetryService(
                port=settings.fc_serial_port,
                baud_rate=settings.fc_baud_rate,
                reconnect_delay_sec=settings.fc_reconnect_delay_sec,
            )
            mavlink_service.start()
            print(
                f"[MAVLink] enabled port={settings.fc_serial_port} "
                f"baud={settings.fc_baud_rate}"
            )

        measurement_source = get_measurement_source()

        for measurement in measurement_source:
            print(f"\n[Gateway] measurement={measurement}")

            if mavlink_service is not None:
                if not isinstance(measurement, SignalMeasurement):
                    raise TypeError(
                        "signal_pipeline must produce SignalMeasurement"
                    )
                flight_data = mavlink_service.latest(
                    settings.fc_position_max_age_sec
                )
                if flight_data is None:
                    print(
                        "[MAVLink] no fresh GPS/battery telemetry; "
                        "signal sample skipped"
                    )
                    continue
                observation = combine_measurements(
                    measurement,
                    flight_data,
                    settings.drone_id,
                )
            else:
                if not isinstance(measurement, SignalObservation):
                    raise TypeError(
                        "mock mode must produce SignalObservation"
                    )
                observation = measurement

            print(f"[Gateway] ready={observation}")

            response = client.send_telemetry(
                observation.telemetry_payload()
            )
            if response is None:
                continue

            drone_id = extract_drone_id(observation.drone_id)
            cell_id = response.get("cell_id")
            rssi = observation.rss_dbm

            client.send_signal(
                drone_id,
                rssi,
                lat=observation.latitude,
                lng=observation.longitude,
                altitude=observation.altitude,
                measured_at=observation.signal_measured_at,
            )

            if uses_rss_detection():
                if rss_detector.check(drone_id, rssi):
                    _try_send_detection(client, drone_id, cell_id, rssi)
            else:
                detected = check_fpga_detection()
                if detected is not None:
                    fpga_drone_id, fpga_rss = detected
                    _try_send_detection(
                        client,
                        fpga_drone_id,
                        cell_id,
                        fpga_rss
                    )

    except KeyboardInterrupt:
        print("\n[stopped] interrupted by user.")

    except Exception as error:
        print(f"\n[fatal error] {error}")

    finally:
        if mavlink_service is not None:
            mavlink_service.close()

        if measurement_source is not None:
            close = getattr(measurement_source, "close", None)
            if close is not None:
                close()

        client.close()
        print("[stopped] gateway connections closed.")


if __name__ == "__main__":
    main()
