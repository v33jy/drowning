# Raspberry Pi Drone Gateway

드론 또는 UART 장치에서 데이터를 수신하고, FastAPI 서버(`/drones/{id}/telemetry`,
`/drones/{id}/signal`, `/detection`)로 전달하는 프로그램입니다.

## 주요 기능

- Mock 테스트 데이터 생성 — 강남역→신논현역 접근 시나리오를 재현해서 하드웨어 없이도
  `DETECTION_MODE=rss_threshold` 탐지 트리거까지 확인 가능
- UART 데이터 수신 및 파싱, 연결이 끊기면(케이블 접촉 불량 등) 죽지 않고 자동 재연결
- 텔레메트리·신호세기 서버 전송, 실패 시 자동 재시도
- 탐지(survivor detection) 이벤트 전송 — FPGA 인터럽트 또는 RSS 임계값, 둘 중 선택 가능
  (그리드 범위 밖이라 cell_id가 없으면 재시도 낭비 없이 보류)
- 원본 패킷 확인용 디버그 모드

## 패킷 형식 (잠정 — 실기기 연결 후 검증 필요)

```text
drone_id,rssi,latitude,longitude,battery
drone-01,-65,37.5012,127.0324,87
```

## 실행

```bash
pip install -r requirements.txt

# 하드웨어 없이 mock 데이터로 테스트
INPUT_MODE=mock SERVER_URL=http://127.0.0.1:8001 python3 main.py

# 실제 UART 장치 연결
INPUT_MODE=serial SERIAL_PORT=/dev/ttyUSB0 BAUD_RATE=115200 \
  SERVER_URL=http://127.0.0.1:8001 python3 main.py

# 실기기 패킷 포맷 확인용 (파싱/전송 없이 원본만 출력)
INPUT_MODE=raw_debug SERIAL_PORT=/dev/ttyUSB0 python3 main.py
```

## 환경변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `GATEWAY_ID` | `gateway-01` | 게이트웨이 식별 이름 |
| `INPUT_MODE` | `mock` | `mock` / `serial` / `raw_debug` |
| `SERIAL_PORT` | `/dev/ttyUSB0` | UART 포트 |
| `BAUD_RATE` | `115200` | UART 속도 |
| `SERVER_URL` | `http://127.0.0.1:8001` | 서버 base URL (경로 접미사 없이) |
| `SEND_INTERVAL` | `2` | mock 모드에서 패킷 생성 간격(초) |
| `REQUEST_TIMEOUT` | `5` | 서버 응답 대기 시간(초) |
| `MAX_RETRIES` | `3` | 전송 재시도 횟수 |
| `DRY_RUN` | `false` | true면 실제 전송 없이 로그만 출력 |
| `DETECTION_MODE` | `fpga` | `fpga`(인터럽트 대기, 아직 미구현) / `rss_threshold`(RSS 임계값으로 자체 판단) |
| `RSS_DETECTION_THRESHOLD` | `-45.0` | `rss_threshold` 모드에서 탐지로 판단할 RSS 임계값(dBm) |
| `DETECTION_COOLDOWN_SEC` | `60` | 같은 드론에 대해 탐지를 다시 트리거하기까지 최소 대기 시간(초) |
| `SERIAL_RECONNECT_DELAY_SEC` | `3` | 시리얼 연결이 끊겼을 때 재연결까지 대기 시간(초) |

## 참고

- `DETECTION_MODE=fpga`가 최종 설계(FPGA가 신호를 식별해 인터럽트를 주면 그걸 그대로 전달)지만,
  FPGA 인터페이스가 아직 확정되지 않아 `check_fpga_detection()`은 자리표시자 상태입니다.
  그 전까지 시연이 필요하면 `DETECTION_MODE=rss_threshold`로 전환해서 쓰면 됩니다.
- 패킷 포맷(필드 개수/순서)은 실제 HW와 확정된 스펙이 아닙니다. 실기기 연결 후
  `INPUT_MODE=raw_debug`로 먼저 원본을 확인하고, 다르면 `packet_parser.py`만 고치면 됩니다.
