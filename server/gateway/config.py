import os
from dataclasses import dataclass


def get_bool_env(name: str, default: bool) -> bool:
    """환경변수 문자열을 True/False로 변환한다."""
    value = os.getenv(name)

    if value is None:
        return default

    return value.lower() in ("1", "true", "yes", "on")


@dataclass
class Settings:
    # 게이트웨이 식별 이름
    gateway_id: str = os.getenv("GATEWAY_ID", "gateway-01")

    # mock: 가짜 데이터 사용 / serial: UART 데이터 사용 / raw_debug: 파싱 없이 원본만 출력
    input_mode: str = os.getenv("INPUT_MODE", "mock")

    # UART 설정
    serial_port: str = os.getenv("SERIAL_PORT", "/dev/ttyUSB0")
    baud_rate: int = int(os.getenv("BAUD_RATE", "115200"))

    # FastAPI 서버 base URL (경로 접미사 없이) — /drones/*, /detection 등 경로별로 client.py가 붙임
    server_url: str = os.getenv("SERVER_URL", "http://127.0.0.1:8001")

    # 테스트 데이터 생성 간격
    send_interval: float = float(os.getenv("SEND_INTERVAL", "2"))

    # 서버 응답 대기 시간
    request_timeout: float = float(os.getenv("REQUEST_TIMEOUT", "5"))

    # 전송 재시도 횟수
    max_retries: int = int(os.getenv("MAX_RETRIES", "3"))

    # True이면 실제 서버로 보내지 않고 출력만 한다.
    dry_run: bool = get_bool_env("DRY_RUN", False)

    # 탐지 판단 방식 — fpga: FPGA 인터럽트 훅 대기 / rss_threshold: RSS 임계값으로 게이트웨이가 자체 판단
    detection_mode: str = os.getenv("DETECTION_MODE", "fpga")

    # rss_threshold 모드에서 탐지로 판단할 RSS 임계값 (dBm)
    rss_detection_threshold: float = float(os.getenv("RSS_DETECTION_THRESHOLD", "-45.0"))

    # 같은 드론에 대해 탐지를 다시 트리거하기까지 최소 대기 시간 (초)
    detection_cooldown_sec: float = float(os.getenv("DETECTION_COOLDOWN_SEC", "60"))


settings = Settings()
