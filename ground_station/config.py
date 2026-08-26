from __future__ import annotations

import os
from dataclasses import dataclass


class ConfigurationError(ValueError):
    """Raised when an environment variable cannot be used safely."""


def _positive_float(name: str, default: str) -> float:
    raw = os.getenv(name, default)
    try:
        value = float(raw)
    except ValueError as error:
        raise ConfigurationError(f"{name} must be a number, got {raw!r}") from error
    if value <= 0:
        raise ConfigurationError(f"{name} must be greater than zero, got {raw!r}")
    return value


def _positive_int(name: str, default: str) -> int:
    raw = os.getenv(name, default)
    try:
        value = int(raw)
    except ValueError as error:
        raise ConfigurationError(f"{name} must be an integer, got {raw!r}") from error
    if value <= 0:
        raise ConfigurationError(f"{name} must be greater than zero, got {raw!r}")
    return value


@dataclass(frozen=True)
class Settings:
    serial_port: str
    baud_rate: int
    serial_timeout_sec: float
    reconnect_delay_sec: float
    log_level: str

    @classmethod
    def from_env(cls) -> "Settings":
        serial_port = os.getenv("SERIAL_PORT", "COM5").strip()
        if not serial_port:
            raise ConfigurationError("SERIAL_PORT must not be empty")
        log_level = os.getenv("LOG_LEVEL", "INFO").upper()
        if log_level not in {"DEBUG", "INFO", "WARNING", "ERROR", "CRITICAL"}:
            raise ConfigurationError(f"LOG_LEVEL is not supported: {log_level!r}")
        return cls(
            serial_port=serial_port,
            baud_rate=_positive_int("BAUD_RATE", "115200"),
            serial_timeout_sec=_positive_float("SERIAL_TIMEOUT_SEC", "1"),
            reconnect_delay_sec=_positive_float(
                "SERIAL_RECONNECT_DELAY_SEC", "2"
            ),
            log_level=log_level,
        )
