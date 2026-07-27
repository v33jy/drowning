import random
import time
from collections.abc import Iterator
from typing import Optional

from client import GatewayClient, extract_drone_id
from config import settings
from packet_parser import PacketParseError, parse_packet


def generate_mock_packets() -> Iterator[str]:
    """
    실제 드론이 없어도 테스트할 수 있도록
    가짜 패킷을 계속 생성한다.
    """

    base_latitude = 37.5012
    base_longitude = 127.0324
    battery = 100

    while True:
        latitude = base_latitude + random.uniform(-0.001, 0.001)
        longitude = base_longitude + random.uniform(-0.001, 0.001)
        rssi = random.randint(-90, -40)

        battery = max(0, battery - random.randint(0, 1))

        packet = (
            f"drone-01,"
            f"{rssi},"
            f"{latitude:.6f},"
            f"{longitude:.6f},"
            f"{battery}"
        )

        yield packet

        time.sleep(settings.send_interval)


def _read_serial_lines() -> Iterator[str]:
    try:
        import serial

    except ImportError as error:
        raise RuntimeError(
            "pyserial이 설치되지 않았습니다. "
            "'pip install pyserial'을 실행하세요."
        ) from error

    print(
        f"[UART 연결] 포트={settings.serial_port}, "
        f"속도={settings.baud_rate}"
    )

    with serial.Serial(
        port=settings.serial_port,
        baudrate=settings.baud_rate,
        timeout=1
    ) as serial_connection:

        while True:
            raw_data = serial_connection.readline()

            if not raw_data:
                continue

            try:
                decoded_data = raw_data.decode(
                    "utf-8",
                    errors="strict"
                ).strip()

            except UnicodeDecodeError:
                print("[수신 오류] UTF-8로 해석할 수 없는 데이터입니다.")
                continue

            if decoded_data:
                yield decoded_data


def read_serial_packets() -> Iterator[str]:
    """라즈베리파이의 USB UART 또는 시리얼 포트에서 한 줄씩 패킷을 읽는다."""
    return _read_serial_lines()


def run_raw_debug() -> None:
    """파싱/전송 없이 시리얼로 들어오는 원본 줄을 그대로 출력한다.

    실제 하드웨어를 연결했을 때 packet_parser.py가 가정하는 포맷(5필드 CSV)이
    실제로 오는 데이터와 맞는지 눈으로 먼저 확인하는 용도.
    """
    print("[디버그 모드] 원본 패킷만 출력하고 서버 전송은 하지 않습니다.")
    for raw_data in _read_serial_lines():
        print(f"[원본] {raw_data!r}")


def get_packet_source() -> Iterator[str]:
    """설정에 따라 mock 또는 UART 입력을 선택한다."""

    mode = settings.input_mode.lower()

    if mode == "mock":
        print("[입력 모드] Mock 테스트 데이터")
        return generate_mock_packets()

    if mode == "serial":
        print("[입력 모드] UART 시리얼 데이터")
        return read_serial_packets()

    raise ValueError(
        f"지원하지 않는 INPUT_MODE입니다: {settings.input_mode}"
    )


def check_fpga_detection() -> Optional[tuple[int, float]]:
    """FPGA가 요구조자 신호를 식별하면 하드웨어 인터럽트를 준다는 게 원래
    설계다 (server/routers/detection.py 참고). 실제 신호가 UART 특수 패킷으로
    오는지 GPIO 인터럽트로 오는지 등은 아직 FPGA 쪽과 확정되지 않아서, 지금은
    자리만 마련해둔 상태.

    FPGA 인터페이스가 정해지면 여기서 그 신호를 읽어
    (drone_id, rss_dbm)을 반환하도록 채우면 된다.
    """
    return None


class RssThresholdDetector:
    """RSS 임계값 기반 탐지 판단 — FPGA 준비 전까지 쓰는 폴백.

    같은 드론에 대해 쿨다운 시간이 지나기 전까지는 다시 트리거하지 않는다.
    """

    def __init__(self, threshold: float, cooldown_sec: float) -> None:
        self.threshold = threshold
        self.cooldown_sec = cooldown_sec
        self._last_triggered: dict[int, float] = {}

    def check(self, drone_id: int, rss_dbm: float) -> bool:
        if rss_dbm < self.threshold:
            return False

        last = self._last_triggered.get(drone_id, 0.0)
        if time.time() - last < self.cooldown_sec:
            return False

        self._last_triggered[drone_id] = time.time()
        return True


def main() -> None:
    print("=" * 50)
    print("Raspberry Pi Drone Gateway 시작")
    print("=" * 50)

    print(f"Gateway ID     : {settings.gateway_id}")
    print(f"Input Mode     : {settings.input_mode}")
    print(f"Server URL     : {settings.server_url}")
    print(f"Detection Mode : {settings.detection_mode}")
    print(f"Dry Run        : {settings.dry_run}")
    print("=" * 50)

    if settings.input_mode.lower() == "raw_debug":
        try:
            run_raw_debug()
        except KeyboardInterrupt:
            print("\n[종료] 사용자가 프로그램을 종료했습니다.")
        except Exception as error:
            print(f"\n[치명적 오류] {error}")
        return

    client = GatewayClient(
        server_url=settings.server_url,
        gateway_id=settings.gateway_id,
        timeout=settings.request_timeout,
        max_retries=settings.max_retries,
        dry_run=settings.dry_run
    )

    rss_detector = RssThresholdDetector(
        threshold=settings.rss_detection_threshold,
        cooldown_sec=settings.detection_cooldown_sec,
    )

    try:
        packet_source = get_packet_source()

        for raw_packet in packet_source:
            print(f"\n[원본 패킷] {raw_packet}")

            try:
                telemetry = parse_packet(raw_packet)

            except PacketParseError as error:
                print(f"[패킷 오류] {error}")
                continue

            print(f"[변환 완료] {telemetry}")

            response = client.send_telemetry(telemetry)
            if response is None:
                continue

            drone_id = extract_drone_id(telemetry["drone_id"])
            cell_id = response.get("cell_id")
            rssi = telemetry["rssi"]

            client.send_signal(drone_id, rssi)

            if settings.detection_mode.lower() == "rss_threshold":
                if rss_detector.check(drone_id, rssi):
                    print(f"[탐지] RSS 임계값 초과 — drone={drone_id} rss={rssi}dBm cell={cell_id}")
                    client.send_detection(drone_id, cell_id, rssi)
            else:
                detected = check_fpga_detection()
                if detected is not None:
                    fpga_drone_id, fpga_rss = detected
                    client.send_detection(fpga_drone_id, cell_id, fpga_rss)

    except KeyboardInterrupt:
        print("\n[종료] 사용자가 프로그램을 종료했습니다.")

    except Exception as error:
        print(f"\n[치명적 오류] {error}")

    finally:
        client.close()
        print("[종료] Gateway 연결을 정리했습니다.")


if __name__ == "__main__":
    main()
