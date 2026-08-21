import os
from dataclasses import dataclass


def get_bool_env(name: str, default: bool) -> bool:
    """Parse an env var string as a bool."""
    value = os.getenv(name)

    if value is None:
        return default

    return value.lower() in ("1", "true", "yes", "on")


@dataclass
class Settings:
    gateway_id: str = os.getenv("GATEWAY_ID", "gateway-01")
    drone_id: str = os.getenv("DRONE_ID", "drone-01")

    # mock: all fake / signal_pipeline: H743 MAVLink + SDR -> FPGA
    input_mode: str = os.getenv("INPUT_MODE", "mock")

    sdr_mode: str = os.getenv("SDR_MODE", "mock")
    sdr_sample_rate_hz: int = int(os.getenv("SDR_SAMPLE_RATE_HZ", "2400000"))
    sdr_center_frequency_hz: int = int(
        os.getenv("SDR_CENTER_FREQUENCY_HZ", "915000000")
    )
    sdr_gain: str = os.getenv("SDR_GAIN", "auto")

    fpga_mode: str = os.getenv("FPGA_MODE", "mock")
    spi_bus: int = int(os.getenv("SPI_BUS", "0"))
    spi_device: int = int(os.getenv("SPI_DEVICE", "0"))
    spi_max_speed_hz: int = int(
        os.getenv("SPI_MAX_SPEED_HZ", "1000000")
    )
    spi_mode: int = int(os.getenv("SPI_MODE", "0"))

    fc_serial_port: str = os.getenv("FC_SERIAL_PORT", "/dev/serial0")
    fc_baud_rate: int = int(os.getenv("FC_BAUD_RATE", "115200"))
    fc_reconnect_delay_sec: float = float(
        os.getenv("FC_RECONNECT_DELAY_SEC", "3")
    )
    fc_position_max_age_sec: float = float(
        os.getenv("FC_POSITION_MAX_AGE_SEC", "3")
    )

    # Server base URL, no path suffix — client.py appends /drones/*, /detection etc.
    server_url: str = os.getenv("SERVER_URL", "http://127.0.0.1:8001")

    send_interval: float = float(os.getenv("SEND_INTERVAL", "2"))
    request_timeout: float = float(os.getenv("REQUEST_TIMEOUT", "5"))
    max_retries: int = int(os.getenv("MAX_RETRIES", "3"))

    dry_run: bool = get_bool_env("DRY_RUN", False)

    # fpga: wait for the FPGA interrupt hook / rss_threshold: gateway decides from RSS itself
    detection_mode: str = os.getenv("DETECTION_MODE", "fpga")
    rss_detection_threshold: float = float(os.getenv("RSS_DETECTION_THRESHOLD", "-45.0"))
    detection_cooldown_sec: float = float(os.getenv("DETECTION_COOLDOWN_SEC", "60"))


settings = Settings()
