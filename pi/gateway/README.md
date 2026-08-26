# Raspberry Pi Drone Gateway

H743와 SDR/FPGA에서 데이터를 수신하고, FastAPI 서버(`/drones/{id}/telemetry`,
`/drones/{id}/signal`, `/detection`)로 전달하는 프로그램입니다.

## 주요 기능

- Mock 테스트 데이터 생성 — 강남역→신논현역 접근 시나리오를 재현해서 하드웨어 없이도
  `DETECTION_MODE=rss_threshold` 탐지 트리거까지 확인 가능
- RTL-SDR IQ 수신 및 FPGA SPI 전송 파이프라인
- H743 MAVLink GPS·고도·배터리를 SDR/FPGA RSS 측정과 결합
- 드론 Heltec LoRa&ESP32의 RSSI/SNR 직렬 출력을 읽어 MAVLink GPS와 결합
- SDR과 FPGA를 각각 mock 또는 실제 장치로 선택 가능
- MAVLink 연결이 끊기면 자동 재연결
- 텔레메트리·신호세기 서버 전송, 실패 시 자동 재시도
- 실기 모드는 FPGA의 `camera_arm`·`detected` 판정을 그대로 사용하고, Mock 모드만 RSS 임계값 사용
- `camera_arm` 이후 Raspberry Pi 카메라의 하드웨어 H.264→RTSP 송출 시작·지연 종료
  (그리드 범위 밖이라 cell_id가 없으면 재시도 낭비 없이 보류)

## 실행

```bash
pip install -r requirements.txt

# 하드웨어 없이 mock 데이터로 테스트
INPUT_MODE=mock SERVER_URL=http://127.0.0.1:8001 python3 main.py

# 실제 H743, RTL-SDR과 FPGA SPI 사용
pip install -r requirements-hardware.txt
INPUT_MODE=signal_pipeline SDR_MODE=real FPGA_MODE=real \
  FC_SERIAL_PORT=/dev/serial0 FC_BAUD_RATE=115200 \
  CAMERA_ENABLED=true CAMERA_RTSP_URL=rtsp://SERVER_IP:8554/drone \
  python3 main.py

# H743는 실제로 연결하고 SDR/FPGA만 mock으로 검증
INPUT_MODE=signal_pipeline SDR_MODE=mock FPGA_MODE=mock \
  FC_SERIAL_PORT=/dev/serial0 FC_BAUD_RATE=115200 \
  CAMERA_ENABLED=false python3 main.py

# 현재 프로젝트 장비: 드론 Heltec RSSI + H743 GPS
INPUT_MODE=lora_serial LORA_SERIAL_PORT=/dev/ttyUSB0 \
  FC_SERIAL_PORT=/dev/serial0 SERVER_URL=http://SERVER_IP:8001 \
  python3 main.py
```

환경변수 예시는 `.env.example`에 있습니다. Python 코드가 `.env` 파일을 직접 읽지는
않으므로 로컬에서는 셸에서 변수를 내보내고, 운영 환경에서는 아래 systemd의
`EnvironmentFile`을 사용합니다. 잘못된 숫자, URL, 실행 모드는 시작 즉시 변수 이름과
함께 오류로 기록됩니다.

## Raspberry Pi systemd 운영

`drowning-gateway.service`의 설치 경로(`/opt/drowning`)가 실제 배포 경로와 다르면
`WorkingDirectory`와 `ExecStart`를 먼저 수정합니다.

```bash
sudo install -d /etc/drowning
sudo install -m 600 .env.example /etc/drowning/gateway.env
sudo install -m 644 drowning-gateway.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now drowning-gateway
sudo journalctl -u drowning-gateway -f
```

서비스는 치명적 오류에 non-zero로 종료되고 `Restart=on-failure`로 재시작됩니다.
SIGTERM을 받으면 진행 중인 HTTP 재시도 대기를 중단하고 카메라, 측정 source,
MAVLink 및 HTTP session을 닫습니다. HTTP는 연결 오류, timeout, 408, 429, 5xx만
재시도하며 일반 4xx는 즉시 실패합니다.

## 환경변수

| 변수 | 기본값 | 설명 |
|---|---|---|
| `GATEWAY_ID` | `gateway-01` | 게이트웨이 식별 이름 |
| `DRONE_ID` | `drone-01` | 서버에 전송할 드론 식별자 |
| `INPUT_MODE` | `mock` | `mock` / `signal_pipeline` / `lora_serial` |
| `LORA_SERIAL_PORT` | `/dev/ttyUSB0` | 드론 Heltec ESP32 직렬 포트 |
| `LORA_SERIAL_BAUD_RATE` | `115200` | Heltec 직렬 속도 |
| `SDR_MODE` | `mock` | `mock` / `real` |
| `SDR_SAMPLE_RATE_HZ` | `2400000` | RTL-SDR sample rate(Hz) |
| `SDR_CENTER_FREQUENCY_HZ` | `915000000` | RTL-SDR 중심 주파수(Hz) |
| `SDR_GAIN` | `auto` | RTL-SDR gain (`auto` 또는 숫자) |
| `FPGA_MODE` | `mock` | `mock` / `real` |
| `SPI_BUS` | `0` | FPGA SPI bus 번호 |
| `SPI_DEVICE` | `0` | FPGA SPI device 번호 |
| `SPI_MAX_SPEED_HZ` | `1000000` | FPGA SPI 최대 속도(Hz) |
| `SPI_MODE` | `0` | FPGA SPI mode |
| `FC_SERIAL_PORT` | `/dev/serial0` | H743 MAVLink UART 포트 |
| `FC_BAUD_RATE` | `115200` | H743 MAVLink UART 속도 |
| `FC_RECONNECT_DELAY_SEC` | `3` | H743 연결이 끊겼을 때 재연결 대기 시간(초) |
| `FC_POSITION_MAX_AGE_SEC` | `3` | RSS와 결합할 수 있는 H743 위치의 최대 경과 시간(초) |
| `SERVER_URL` | `http://127.0.0.1:8001` | 서버 base URL (경로 접미사 없이) |
| `SEND_INTERVAL` | `2` | mock 모드에서 패킷 생성 간격(초) |
| `REQUEST_TIMEOUT` | `5` | 서버 응답 대기 시간(초) |
| `MAX_RETRIES` | `3` | 전송 재시도 횟수 |
| `DRY_RUN` | `false` | true면 실제 전송 없이 로그만 출력 |
| `DETECTION_MODE` | `fpga` | Mock 모드에서만 `rss_threshold` 선택 가능. 실기 모드는 FPGA 결과 고정 |
| `RSS_DETECTION_THRESHOLD` | `-45.0` | Mock 모드의 탐지 임계값(dBm) |
| `MOCK_CAMERA_ARM_THRESHOLD` | `-55.0` | Mock 모드에서 카메라 준비 플래그를 켜는 임계값(dBm) |
| `DETECTION_COOLDOWN_SEC` | `60` | 같은 드론에 대해 탐지를 다시 트리거하기까지 최소 대기 시간(초) |
| `CAMERA_ENABLED` | `false` | FPGA 플래그에 따른 카메라 송출 제어 사용 여부 |
| `CAMERA_HOLD_SECONDS` | `20` | 마지막 활성 플래그 이후 송출 유지 시간(초) |
| `CAMERA_WIDTH` / `CAMERA_HEIGHT` | `854` / `480` | Pi 4B 부하를 고려한 송출 해상도 |
| `CAMERA_FPS` | `10` | H.264 송출 프레임률 |
| `CAMERA_BITRATE` | `800000` | H.264 비트레이트(bps) |
| `CAMERA_RTSP_URL` | `rtsp://127.0.0.1:8554/drone` | MediaMTX RTSP 게시 주소 |

## 테스트

```bash
python3 -m unittest discover -s tests
```

MAVLink 변환·SDR/FPGA 파이프라인·서버 전송 로직을 다룹니다
(실제 장비와 네트워크 없이 동작).

## 참고

- Pi와 FPGA 사이 결과 패킷 v2에는 `camera_arm`과 `detected`가 들어갑니다. Pi는 이를 장치 제어와
  서버 전송에만 사용하며 실기 모드에서 신호 판정을 다시 수행하지 않습니다.
- Raspberry Pi 측 `RtlSdrSource`와 `SpiFpgaTransport`는 구현되어 있습니다. 실제 종단 간 연결에는
  FPGA RTL의 SPI slave, 연산 완료 READY, 결과 패킷 직렬화가 필요합니다. FPGA→Heltec UART
  출력도 동일 판정 결과를 별도 전송하는 하드웨어 연결 작업으로 남아 있습니다.
