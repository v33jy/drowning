import time
from typing import Any, Optional

import requests


def extract_drone_id(raw_drone_id: str) -> int:
    """"drone-01" 형태의 문자열에서 정수 드론 ID를 뽑는다."""
    return int(raw_drone_id.replace("drone-", ""))


class GatewayClient:
    """서버의 telemetry/signal/detection 세 엔드포인트를 재시도 포함해서 호출한다."""

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
        텔레메트리 데이터를 서버로 전송한다.

        성공하면 서버 응답(entry, cell_id 포함)을 그대로 돌려준다 — 호출자가
        이걸로 탐지 이벤트에 필요한 cell_id를 별도 조회 없이 바로 쓸 수 있다.
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
            print(f"[데이터 오류] 잘못된 텔레메트리 형식: {error}")
            print(f"[수신 데이터] {telemetry}")
            return None

        return self._post_with_retry(f"/drones/{drone_id}/telemetry", payload)

    def send_signal(self, drone_id: int, rss_dbm: float) -> bool:
        """RSS 신호 세기를 서버로 전송한다."""
        result = self._post_with_retry(f"/drones/{drone_id}/signal", {"rss_dbm": rss_dbm})
        return result is not None

    def send_detection(self, drone_id: int, cell_id: Optional[str], rss_dbm: float) -> Optional[dict]:
        """탐지 이벤트를 서버로 전송한다 (VoIP 세션이 열림)."""
        payload = {
            "drone_id": drone_id,
            "cell_id": cell_id,
            "rss_dbm": rss_dbm,
            "stream_url": None,
        }
        return self._post_with_retry("/detection", payload)

    def close(self) -> None:
        """HTTP 연결을 정리한다."""
        self.session.close()

    # -- Private --

    def _post_with_retry(self, path: str, payload: dict) -> Optional[dict]:
        """재시도/백오프 포함 공통 POST 헬퍼. 성공 시 응답 JSON(dict, 없으면 {})을
        반환하고, 재시도를 다 써도 실패하면 None을 반환한다."""
        url = f"{self.server_url}{path}"

        if self.dry_run:
            print("[DRY RUN] 서버 전송 생략")
            print(f"[GATEWAY] {self.gateway_id}")
            print(f"[URL] {url}")
            print(f"[PAYLOAD] {payload}")
            return {}

        for attempt in range(1, self.max_retries + 1):
            try:
                response = self.session.post(url, json=payload, timeout=self.timeout)
                response.raise_for_status()

                print(f"[전송 성공] {url}  상태 코드: {response.status_code}")
                try:
                    return response.json()
                except ValueError:
                    return {}

            except requests.RequestException as error:
                print(f"[전송 실패] {url}  {attempt}/{self.max_retries}회: {error}")

                if hasattr(error, "response") and error.response is not None:
                    print(f"[서버 응답] {error.response.text}")

                if attempt < self.max_retries:
                    wait_seconds = 2 ** (attempt - 1)
                    print(f"[재시도 대기] {wait_seconds}초")
                    time.sleep(wait_seconds)

        print(f"[전송 포기] {url} 최대 재시도 횟수를 초과했습니다.")
        return None
