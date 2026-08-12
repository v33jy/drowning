import time
import uuid
from typing import Any, Optional

import requests


def extract_drone_id(raw_drone_id: str) -> int:
    """Extract the integer drone ID from a "drone-01" style string."""
    return int(raw_drone_id.replace("drone-", ""))


class GatewayClient:
    """Calls the server's telemetry/signal/detection endpoints, with retry."""

    def __init__(
        self,
        server_url: str,
        gateway_id: str,
        timeout: float = 5,
        max_retries: int = 3,
        dry_run: bool = True
    ) -> None:
        self.server_url = server_url.rstrip("/")
        self.gateway_id = gateway_id
        self.timeout = timeout
        self.max_retries = max_retries
        self.dry_run = dry_run

        self.session = requests.Session()

    def send_telemetry(self, telemetry: dict[str, Any]) -> Optional[dict]:
        """
        Send telemetry to the server.

        On success, returns the server response as-is (includes cell_id) so
        the caller can use it for a detection event without a separate lookup.
        """

        try:
            drone_id = extract_drone_id(telemetry["drone_id"])

            payload = {
                "lat": float(
                    telemetry.get("lat", telemetry.get("latitude"))
                ),
                "lng": float(
                    telemetry.get("lng", telemetry.get("longitude"))
                ),
                "altitude": float(telemetry.get("altitude", 0.0)),
                "battery": int(telemetry["battery"]),
                "status": str(telemetry.get("status", "active"))
            }

        except (KeyError, TypeError, ValueError) as error:
            print(f"[data error] invalid telemetry format: {error}")
            print(f"[received] {telemetry}")
            return None

        return self._post_with_retry(f"/drones/{drone_id}/telemetry", payload)

    def send_signal(
        self,
        drone_id: int,
        rss_dbm: float,
        *,
        lat: Optional[float] = None,
        lng: Optional[float] = None,
        altitude: Optional[float] = None,
        measured_at: Optional[float] = None,
    ) -> bool:
        """Send an RSS reading with the position/time captured for the sample."""
        payload = {
            "measurement_id": str(uuid.uuid4()),
            "rss_dbm": rss_dbm,
        }
        if lat is not None and lng is not None:
            payload.update({"lat": lat, "lng": lng})
        if altitude is not None:
            payload["altitude"] = altitude
        if measured_at is not None:
            payload["measured_at"] = measured_at
        result = self._post_with_retry(f"/drones/{drone_id}/signal", payload)
        return result is not None

    def send_detection(self, drone_id: int, cell_id: Optional[str], rss_dbm: float) -> Optional[dict]:
        """Send a detection event to the server (opens a VoIP session)."""
        payload = {
            "drone_id": drone_id,
            "cell_id": cell_id,
            "rss_dbm": rss_dbm,
            "stream_url": None,
        }
        return self._post_with_retry("/detection", payload)

    def close(self) -> None:
        """Close the HTTP session."""
        self.session.close()

    # -- Private --

    def _post_with_retry(self, path: str, payload: dict) -> Optional[dict]:
        """Shared POST helper with retry/backoff. Returns the response JSON
        (dict, {} if empty) on success, or None once retries are exhausted."""
        url = f"{self.server_url}{path}"

        if self.dry_run:
            print("[DRY RUN] skipping server send")
            print(f"[GATEWAY] {self.gateway_id}")
            print(f"[URL] {url}")
            print(f"[PAYLOAD] {payload}")
            return {}

        for attempt in range(1, self.max_retries + 1):
            try:
                response = self.session.post(url, json=payload, timeout=self.timeout)
                response.raise_for_status()

                print(f"[sent] {url}  status: {response.status_code}")
                try:
                    return response.json()
                except ValueError:
                    return {}

            except requests.RequestException as error:
                print(f"[send failed] {url}  {attempt}/{self.max_retries}: {error}")

                if hasattr(error, "response") and error.response is not None:
                    print(f"[server response] {error.response.text}")

                if attempt < self.max_retries:
                    wait_seconds = 2 ** (attempt - 1)
                    print(f"[retry wait] {wait_seconds}s")
                    time.sleep(wait_seconds)

        print(f"[gave up] {url} exceeded max retries.")
        return None
