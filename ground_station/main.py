"""
지상국 LoRa 게이트웨이
======================
드론 WiFi가 닿지 않을 때를 대비한 폴백 경로 — 드론 탑재 FPGA가 UART로 Heltec
LoRa 송신 보드에 보낸 탐지 결과를, 지상국의 Heltec LoRa 수신 보드가 무선으로
받아 USB로 이 노트북에 넘겨준다. 여기서 그 값을 읽어 기존 서버(server/)로
전달한다.

이전엔 이 파일이 자기 FastAPI 앱을 띄워서 GET /telemetry/latest로 조회만
되게 해뒀었다 — 그러면 관제 앱은 오직 server/의 /ws/control만 보고 있어서
화면에 아무것도 안 뜬다. pi/gateway와 같은 패턴(읽어서 server로 POST)으로
바꿔야 관제 앱까지 실제로 데이터가 이어진다.
"""

import logging
import signal
import threading
from typing import Optional

from config import ConfigurationError, Settings
from logging_config import configure_logging

logger = logging.getLogger(__name__)


def parse_fpga_data(raw_data: str) -> Optional[dict]:
    """
    예시 데이터: DET,1,13,08193 (감지여부, fft_bin, magnitude)

    FPGA가 UART로 내보내는 포맷 — 아직 위치(lat/lng) 필드는 없다
    (라즈베리파이->FPGA SPI 규격에 위치가 실리게 되면 여기도 같이 늘어나야 함).
    """
    parts = raw_data.split(",")

    if len(parts) != 4 or parts[0] != "DET":
        return None

    try:
        return {
            "detected": bool(int(parts[1])),
            "fft_bin": int(parts[2]),
            "magnitude": int(parts[3]),
        }

    except ValueError:
        logger.warning("Invalid FPGA data: %r", raw_data)
        return None


def report_detection(detection: dict) -> None:
    """
    서버의 POST /detection은 cell_id가 필수인데, cell_id는 위치(lat/lng)로만
    계산할 수 있다. 지금 LoRa 메시지엔 위치가 안 실려있어서 cell_id를 구할
    방법이 없다 — 그래서 아직은 서버로 못 보내고 로컬에만 기록한다.

    TODO: 라즈베리파이->FPGA SPI 규격과 FPGA->LoRa UART 메시지에 위치 필드가
    추가되면(하드웨어 쪽 작업), 이 함수가 requests로 서버의 POST /detection에
    cell_id를 채워서 보내도록 채울 것 — pi/gateway/client.py의 GatewayClient
    패턴 참고.
    """
    logger.info(
        "Detection held locally because cell_id is unavailable: "
        "detected=%s fft_bin=%s magnitude=%s",
        detection["detected"],
        detection["fft_bin"],
        detection["magnitude"],
    )


def handle_line(line: str) -> None:
    logger.debug("ESP32: %s", line)

    if line.startswith("LORA RX DATA:"):
        data = line.replace("LORA RX DATA:", "", 1).strip()
        detection = parse_fpga_data(data)

        if detection is not None:
            report_detection(detection)

    elif line.startswith("RSSI:") or line.startswith("SNR:"):
        # LoRa 무선 링크 자체의 품질 지표(두 Heltec 보드 사이 수신 감도) —
        # 드론이 감지한 목표 신호의 세기(rss_dbm)와는 다른 값이라 서버로는
        # 안 보내고, 지상국에서 링크 상태 확인용으로만 출력한다.
        logger.info("LoRa link: %s", line)


def run_serial_reader(settings: Settings, stop_event: threading.Event) -> None:
    """UART 한 줄씩 읽는다. 연결이 끊기면(케이블 재꽂기 등) 죽지 않고
    자동으로 재연결한다 — pi/gateway의 시리얼 재연결 로직과 동일한 패턴.

    pyserial을 함수 안에서 import하는 이유도 pi/gateway와 동일 — 시리얼을
    실제로 열 때만 필요하니, 이 함수를 안 쓰는 유닛 테스트는 pyserial 없이도
    돌아가게 하기 위함."""
    from serial import Serial, SerialException

    while not stop_event.is_set():
        try:
            logger.info(
                "Connecting serial port=%s baud=%s",
                settings.serial_port,
                settings.baud_rate,
            )

            with Serial(
                settings.serial_port,
                settings.baud_rate,
                timeout=settings.serial_timeout_sec,
            ) as receiver:
                # ESP32가 USB 연결 시 재부팅될 수 있어서 잠시 대기
                if stop_event.wait(2):
                    return
                logger.info("Serial connected")

                while not stop_event.is_set():
                    raw_line = receiver.readline()

                    if not raw_line:
                        continue

                    line = raw_line.decode("utf-8", errors="replace").strip()

                    if line:
                        handle_line(line)

        except (SerialException, OSError) as error:
            logger.warning(
                "Serial disconnected: %s; retrying in %.1fs",
                error,
                settings.reconnect_delay_sec,
            )
            stop_event.wait(settings.reconnect_delay_sec)


def main() -> int:
    try:
        settings = Settings.from_env()
    except ConfigurationError as error:
        configure_logging("ERROR")
        logger.error("Invalid configuration: %s", error)
        return 2

    configure_logging(settings.log_level)
    stop_event = threading.Event()

    def request_stop(signum, _frame) -> None:
        logger.info("Received signal %s; stopping", signum)
        stop_event.set()

    signal.signal(signal.SIGINT, request_stop)
    signal.signal(signal.SIGTERM, request_stop)
    logger.info("Ground station starting serial_port=%s", settings.serial_port)

    try:
        run_serial_reader(settings, stop_event)
    except Exception:
        logger.exception("Ground station stopped unexpectedly")
        return 1
    finally:
        stop_event.set()
        logger.info("Ground station stopped")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
