import os
from dataclasses import dataclass, field
from urllib.parse import urlparse


class ConfigError(ValueError):
    """Raised when a gateway environment variable is invalid."""


def _text(name: str, default: str) -> str:
    value = os.getenv(name, default).strip()
    if not value:
        raise ConfigError(f"{name} must not be empty")
    return value


def _int(
    name: str,
    default: int,
    *,
    minimum: int = 0,
    maximum: int | None = None,
) -> int:
    raw = os.getenv(name, str(default))
    try:
        value = int(raw)
    except ValueError as error:
        raise ConfigError(f"{name} must be an integer, got {raw!r}") from error
    if value < minimum:
        raise ConfigError(f"{name} must be at least {minimum}, got {value}")
    if maximum is not None and value > maximum:
        raise ConfigError(f"{name} must be at most {maximum}, got {value}")
    return value


def _float(name: str, default: float, *, minimum: float = 0.0) -> float:
    raw = os.getenv(name, str(default))
    try:
        value = float(raw)
    except ValueError as error:
        raise ConfigError(f"{name} must be a number, got {raw!r}") from error
    if value < minimum:
        raise ConfigError(f"{name} must be at least {minimum}, got {value}")
    return value


def _number(name: str, default: float) -> float:
    raw = os.getenv(name, str(default))
    try:
        return float(raw)
    except ValueError as error:
        raise ConfigError(f"{name} must be a number, got {raw!r}") from error


def get_bool_env(name: str, default: bool) -> bool:
    value = os.getenv(name)
    if value is None:
        return default
    normalized = value.strip().lower()
    if normalized in ("1", "true", "yes", "on"):
        return True
    if normalized in ("0", "false", "no", "off"):
        return False
    raise ConfigError(f"{name} must be true or false, got {value!r}")


def _choice(name: str, default: str, choices: set[str]) -> str:
    value = _text(name, default).lower()
    if value not in choices:
        allowed = ", ".join(sorted(choices))
        raise ConfigError(f"{name} must be one of {allowed}, got {value!r}")
    return value


def _url(name: str, default: str, schemes: set[str]) -> str:
    value = _text(name, default).rstrip("/")
    parsed = urlparse(value)
    if parsed.scheme not in schemes or not parsed.hostname:
        allowed = "/".join(sorted(schemes))
        raise ConfigError(f"{name} must be a valid {allowed} URL, got {value!r}")
    return value


@dataclass
class Settings:
    gateway_id: str = field(default_factory=lambda: _text("GATEWAY_ID", "gateway-01"))
    drone_id: str = field(default_factory=lambda: _text("DRONE_ID", "drone-01"))
    input_mode: str = field(default_factory=lambda: _choice("INPUT_MODE", "mock", {"mock", "signal_pipeline", "lora_serial"}))
    lora_serial_port: str = field(default_factory=lambda: _text("LORA_SERIAL_PORT", "/dev/ttyUSB0"))
    lora_serial_baud_rate: int = field(default_factory=lambda: _int("LORA_SERIAL_BAUD_RATE", 115200, minimum=1))
    lora_serial_timeout_sec: float = field(default_factory=lambda: _float("LORA_SERIAL_TIMEOUT_SEC", 1, minimum=0.01))
    sdr_mode: str = field(default_factory=lambda: _choice("SDR_MODE", "mock", {"mock", "real"}))
    sdr_sample_rate_hz: int = field(default_factory=lambda: _int("SDR_SAMPLE_RATE_HZ", 2400000, minimum=1))
    sdr_center_frequency_hz: int = field(default_factory=lambda: _int("SDR_CENTER_FREQUENCY_HZ", 915000000, minimum=1))
    sdr_gain: str = field(default_factory=lambda: _text("SDR_GAIN", "auto"))
    fpga_mode: str = field(default_factory=lambda: _choice("FPGA_MODE", "mock", {"mock", "real"}))
    spi_bus: int = field(default_factory=lambda: _int("SPI_BUS", 0))
    spi_device: int = field(default_factory=lambda: _int("SPI_DEVICE", 0))
    spi_max_speed_hz: int = field(default_factory=lambda: _int("SPI_MAX_SPEED_HZ", 1000000, minimum=1))
    spi_mode: int = field(default_factory=lambda: _int("SPI_MODE", 0, maximum=3))
    fc_serial_port: str = field(default_factory=lambda: _text("FC_SERIAL_PORT", "/dev/serial0"))
    fc_baud_rate: int = field(default_factory=lambda: _int("FC_BAUD_RATE", 115200, minimum=1))
    fc_reconnect_delay_sec: float = field(default_factory=lambda: _float("FC_RECONNECT_DELAY_SEC", 3, minimum=0.01))
    fc_position_max_age_sec: float = field(default_factory=lambda: _float("FC_POSITION_MAX_AGE_SEC", 3, minimum=0.01))
    server_url: str = field(default_factory=lambda: _url("SERVER_URL", "http://127.0.0.1:8001", {"http", "https"}))
    send_interval: float = field(default_factory=lambda: _float("SEND_INTERVAL", 2, minimum=0.01))
    request_timeout: float = field(default_factory=lambda: _float("REQUEST_TIMEOUT", 5, minimum=0.01))
    max_retries: int = field(default_factory=lambda: _int("MAX_RETRIES", 3, minimum=1, maximum=10))
    dry_run: bool = field(default_factory=lambda: get_bool_env("DRY_RUN", False))
    detection_mode: str = field(default_factory=lambda: _choice("DETECTION_MODE", "fpga", {"fpga", "rss_threshold"}))
    rss_detection_threshold: float = field(default_factory=lambda: _number("RSS_DETECTION_THRESHOLD", -45.0))
    detection_cooldown_sec: float = field(default_factory=lambda: _float("DETECTION_COOLDOWN_SEC", 60))
    mock_camera_arm_threshold: float = field(default_factory=lambda: _number("MOCK_CAMERA_ARM_THRESHOLD", -55.0))
    camera_enabled: bool = field(default_factory=lambda: get_bool_env("CAMERA_ENABLED", False))
    camera_hold_seconds: float = field(default_factory=lambda: _float("CAMERA_HOLD_SECONDS", 20))
    camera_width: int = field(default_factory=lambda: _int("CAMERA_WIDTH", 854, minimum=16))
    camera_height: int = field(default_factory=lambda: _int("CAMERA_HEIGHT", 480, minimum=16))
    camera_fps: int = field(default_factory=lambda: _int("CAMERA_FPS", 10, minimum=1))
    camera_bitrate: int = field(default_factory=lambda: _int("CAMERA_BITRATE", 800000, minimum=1000))
    camera_rtsp_url: str = field(default_factory=lambda: _url("CAMERA_RTSP_URL", "rtsp://127.0.0.1:8554/drone", {"rtsp", "rtsps"}))


settings = Settings()
