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

    # mock: fake data / serial: real UART / raw_debug: print raw lines only
    input_mode: str = os.getenv("INPUT_MODE", "mock")

    serial_port: str = os.getenv("SERIAL_PORT", "/dev/ttyUSB0")
    baud_rate: int = int(os.getenv("BAUD_RATE", "115200"))

    # Reconnect delay after a serial disconnect — drone vibration can drop
    # the USB-serial link momentarily.
    serial_reconnect_delay_sec: float = float(os.getenv("SERIAL_RECONNECT_DELAY_SEC", "3"))

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
