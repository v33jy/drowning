"""Read LoRa packet RSSI/SNR reports emitted by the drone-side Heltec ESP32."""

from __future__ import annotations

import time
from dataclasses import dataclass
from typing import Iterator, Optional

from measurement import SignalMeasurement


@dataclass(frozen=True)
class LoRaReading:
    payload: str
    rss_dbm: float
    snr_db: float


class LoRaLineParser:
    """Parse both the current multiline firmware log and compact wire format."""

    def __init__(self) -> None:
        self._payload: Optional[str] = None
        self._rss_dbm: Optional[float] = None

    def feed(self, line: str) -> Optional[LoRaReading]:
        text = line.strip()
        if not text:
            return None

        if text.startswith("LORA_SAMPLE|"):
            parts = text.split("|", 3)
            if len(parts) != 4:
                return None
            try:
                return LoRaReading(
                    payload=parts[3],
                    rss_dbm=float(parts[1]),
                    snr_db=float(parts[2]),
                )
            except ValueError:
                return None

        if text.startswith("LORA RX DATA:"):
            self._payload = text.partition(":")[2].strip()
            self._rss_dbm = None
            return None
        if text.startswith("RSSI:"):
            try:
                self._rss_dbm = float(text.partition(":")[2].strip())
            except ValueError:
                self._rss_dbm = None
            return None
        if text.startswith("SNR:") and self._payload is not None and self._rss_dbm is not None:
            try:
                reading = LoRaReading(
                    payload=self._payload,
                    rss_dbm=self._rss_dbm,
                    snr_db=float(text.partition(":")[2].strip()),
                )
            except ValueError:
                return None
            finally:
                self._payload = None
                self._rss_dbm = None
            return reading
        return None


class LoRaSerialSource:
    def __init__(self, port: str, baud_rate: int, timeout_sec: float = 1) -> None:
        self.port = port
        self.baud_rate = baud_rate
        self.timeout_sec = timeout_sec
        self._serial = None

    def measurements(self) -> Iterator[SignalMeasurement]:
        try:
            import serial
        except ImportError as error:
            raise RuntimeError(
                "pyserial is required for INPUT_MODE=lora_serial"
            ) from error

        parser = LoRaLineParser()
        self._serial = serial.Serial(
            self.port,
            self.baud_rate,
            timeout=self.timeout_sec,
        )
        try:
            while True:
                raw = self._serial.readline()
                if not raw:
                    continue
                reading = parser.feed(raw.decode("utf-8", errors="replace"))
                if reading is None:
                    continue
                print(
                    f"[LORA] payload={reading.payload!r} "
                    f"rss={reading.rss_dbm:.1f}dBm snr={reading.snr_db:.1f}dB"
                )
                yield SignalMeasurement(
                    rss_dbm=reading.rss_dbm,
                    measured_at=time.time(),
                )
        finally:
            self.close()

    def close(self) -> None:
        if self._serial is not None:
            self._serial.close()
            self._serial = None
