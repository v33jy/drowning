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

import os
import time
from typing import Optional

SERIAL_PORT = os.getenv("SERIAL_PORT", "COM5")
BAUD_RATE = int(os.getenv("BAUD_RATE", "115200"))
SERIAL_RECONNECT_DELAY_SEC = float(os.getenv("SERIAL_RECONNECT_DELAY_SEC", "2"))


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
        print(f"[parse error] {raw_data!r}")
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
    print(
        f"[detection — 서버 전송 보류, cell_id 없음] "
        f"detected={detection['detected']} "
        f"fft_bin={detection['fft_bin']} "
        f"magnitude={detection['magnitude']}"
    )


def handle_line(line: str) -> None:
    print("[ESP32]", line)

    if line.startswith("LORA RX DATA:"):
        data = line.replace("LORA RX DATA:", "", 1).strip()
        detection = parse_fpga_data(data)

        if detection is not None:
            report_detection(detection)

    elif line.startswith("RSSI:") or line.startswith("SNR:"):
        # LoRa 무선 링크 자체의 품질 지표(두 Heltec 보드 사이 수신 감도) —
        # 드론이 감지한 목표 신호의 세기(rss_dbm)와는 다른 값이라 서버로는
        # 안 보내고, 지상국에서 링크 상태 확인용으로만 출력한다.
        print("[link]", line)


def run_serial_reader() -> None:
    """UART 한 줄씩 읽는다. 연결이 끊기면(케이블 재꽂기 등) 죽지 않고
    자동으로 재연결한다 — pi/gateway의 시리얼 재연결 로직과 동일한 패턴.

    pyserial을 함수 안에서 import하는 이유도 pi/gateway와 동일 — 시리얼을
    실제로 열 때만 필요하니, 이 함수를 안 쓰는 유닛 테스트는 pyserial 없이도
    돌아가게 하기 위함."""
    from serial import Serial, SerialException

    while True:
        try:
            print(f"[SERIAL connecting] port={SERIAL_PORT}, baud={BAUD_RATE}")

            with Serial(SERIAL_PORT, BAUD_RATE, timeout=1) as receiver:
                # ESP32가 USB 연결 시 재부팅될 수 있어서 잠시 대기
                time.sleep(2)
                print("[SERIAL connected]")

                while True:
                    raw_line = receiver.readline()

                    if not raw_line:
                        continue

                    line = raw_line.decode("utf-8", errors="replace").strip()

                    if line:
                        handle_line(line)

        except SerialException as error:
            print(
                f"[SERIAL disconnected] {error} — "
                f"retrying in {SERIAL_RECONNECT_DELAY_SEC}s"
            )
            time.sleep(SERIAL_RECONNECT_DELAY_SEC)


def main() -> None:
    print("=" * 50)
    print("지상국 LoRa 게이트웨이 시작")
    print(f"Serial Port : {SERIAL_PORT}")
    print("=" * 50)

    try:
        run_serial_reader()

    except KeyboardInterrupt:
        print("\n[stopped] interrupted by user.")


if __name__ == "__main__":
    main()
