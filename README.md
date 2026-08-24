# drowning — 단일 드론 기반 재난 수색·요구조자 관제 시스템

[![CI](https://github.com/v33jy/drowning/actions/workflows/ci.yml/badge.svg)](https://github.com/v33jy/drowning/actions/workflows/ci.yml)

드론이 재난 지역 상공을 돌아다니며 통신 신호를 릴레이하고, 요구조자를 찾아내면 관제 앱에 위치와 영상을 바로 띄워주는 시스템입니다.

## 구조

```
[드론 시뮬레이터]          [FastAPI 서버]           [Flutter 관제 앱]
  scenario.py   ──HTTP──▶  /drones/{id}/telemetry  ──WebSocket──▶  지도·드론 마커
  (위치, RSS)   ──HTTP──▶  /drones/{id}/signal     ──WebSocket──▶  구조 탐색 지도
                ──HTTP──▶  /detection              ──WebSocket──▶  탐지 알림 팝업

[라즈베리파이 (pi/)]      (H743·SDR·FPGA·카메라 연동)
  pi/gateway/main.py      ──HTTP──▶  위와 동일 (telemetry·signal·detection)
  FPGA camera_arm/detected ─▶ rpicam-vid(H.264) ──RTSP──▶ MediaMTX
                                                    └──WebRTC/WHEP──▶ 앱 영상
```

- `server/` — FastAPI 백엔드. 드론 텔레메트리·신호·탐지를 받아 WebSocket으로 관제 앱에 전달
- `app/` — Flutter 관제 앱 (iPad 대상, 가로 고정). 단일 운용 드론의 위치와 상태, 구조 탐색 구역, 탐지 팝업, 음성 연결, 영상 프리뷰 및 수색 활동 기록을 보여줌
- `pi/` — 실제 라즈베리파이에 올려서 실행하는 코드. `gateway/`가 H743 텔레메트리와 FPGA 판정 결과를 전달하고 필요할 때만 하드웨어 H.264 송출 프로세스를 제어

## 실행 방법

### 1. 서버

```bash
cd server
pip install -r requirements.txt
GRID_LAT_MIN=37.490 GRID_LAT_MAX=37.515 \
GRID_LNG_MIN=127.020 GRID_LNG_MAX=127.040 \
python3 -m uvicorn main:app --host 0.0.0.0 --port 8001
```

`GRID_*` 환경변수는 관제 구역의 위경도 범위를 정하는 값이라, 위 값 그대로 써도 되고 원하는 지역으로 바꿔도 됩니다. 서버가 뜨면 `http://localhost:8001`에서 REST API, `ws://localhost:8001/ws/control`에서 WebSocket이 열립니다.

영상 중계와 녹화는 MediaMTX가 담당합니다. 저장 위치와 보존 시간은 루트의 `mediamtx.yml`에서 설정합니다. 기존 JPEG 프레임 중계와 메모리 영상 보관 기능은 제거했습니다.

### 2. 관제 앱

서버가 켜진 상태에서 별도 터미널로:

```bash
cd app
flutter run --device-id {시뮬레이터_또는_기기_ID} \
  --dart-define=SERVER_HOST=localhost \
  --dart-define=HTTP_PORT=8001 \
  --dart-define=MEDIA_HTTP_PORT=8889
```

앱은 켜지자마자 서버에 격자 정보를 요청하고 WebSocket을 연결합니다 — 서버를 먼저 안 켜두면 "Cannot reach server" 화면이 뜹니다.

### 3. 실시간 영상 스트리밍

실기에서는 Raspberry Pi 카메라 영상을 `rpicam-vid`로 하드웨어 H.264 인코딩한 뒤 RTSP로
MediaMTX에 전달합니다. 관제 앱은 탐지 이벤트의 `stream_url`을 사용해 MediaMTX의 WHEP
엔드포인트에 연결하고 WebRTC로 현장 영상을 재생합니다.

```text
Raspberry Pi Camera
  → rpicam-vid (H.264 하드웨어 인코딩)
  → RTSP
  → MediaMTX
  → WebRTC/WHEP
  → 관제 앱 탐지 패널
```

- FPGA 결과의 `camera_arm`이 활성화되면 Pi가 탐지 전에 송출을 준비해 초기 영상 대기 시간을 줄입니다.
- `detected`가 활성화되면 서버가 영상 URL을 포함한 탐지 이벤트를 관제 앱에 전달합니다.
- 신호가 약해진 뒤에도 기본 20초 동안 송출을 유지해 짧은 신호 변화로 카메라가 반복 재기동되는 것을 방지합니다.
- 개발 PC에서는 아래 드론 시나리오 절의 `pi/mock_video_stream.py`로 같은 RTSP→WHEP 경로를 테스트합니다.

영상 중계 서버는 먼저 실행해야 합니다.

```bash
mediamtx mediamtx.yml
```

기본적으로 서버는 탐지 요청을 받은 API 서버의 호스트와 `8889` 포트를 조합해 관제
단말에서 접근 가능한 WHEP URL을 생성합니다. MediaMTX가 별도 장비나 포트에서 실행되면
서버 실행 전에 `MEDIAMTX_WHEP_URL`을 관제 단말에서 접근 가능한 전체 URL로 지정합니다.

```bash
MEDIAMTX_WHEP_URL=http://192.168.0.30:8889/drone/whep \
python3 -m uvicorn main:app --host 0.0.0.0 --port 8001
```

### 4. 요구조자 앱과 음성 통화

탐지가 발생하면 서버가 탐지별 통화 세션을 만들고 대기 중인 요구조자 앱에 수신 이벤트를
전달합니다. 관제 앱의 탐지 패널에서 `전화 연결`을 누르면 WebSocket으로 WebRTC 연결 정보를
교환하며, 연결 후 음성은 서버를 거치지 않고 관제 앱과 요구조자 앱 사이에서 직접 전송됩니다.

서버가 켜진 상태에서 요구조자 단말에 앱을 실행합니다. 실제 단말에서는 `localhost` 대신
같은 네트워크에 있는 서버의 IP 주소를 사용해야 합니다.

```bash
cd survivor_app
flutter run --device-id {요구조자_기기_ID} \
  --dart-define=SERVER_HOST={서버_IP} \
  --dart-define=HTTP_PORT=8001
```

- 관제 앱은 연속 `음성 전달`과 `눌러서 말하기` 방식을 선택할 수 있습니다.
- 요구조자 앱은 버튼을 누르고 있는 동안에만 마이크 음성을 전송합니다.
- 일시적인 연결 실패는 2초 간격으로 최대 3회 자동 재연결하고, 이후에는 수동 재시도를 표시합니다.
- 마이크 권한이 꺼져 있으면 기기 설정으로 이동하도록 안내하며, 앱으로 돌아오면 권한을 다시 확인하고 통화를 재시도합니다.
- 관제 앱은 송신 중 마이크 입력 감지 여부와 입력 레벨을 표시합니다.

현재 PeerConnection에는 STUN/TURN 서버를 설정하지 않았으므로 관제 단말, 요구조자 단말,
서버가 같은 네트워크에 있는 테스트 환경을 전제로 합니다. 외부 네트워크 간 통화에는
STUN/TURN 구성과 배포 환경의 HTTPS/WSS 적용이 필요합니다.

### 5. 드론 시뮬레이터

데모용 시나리오 스크립트로 드론의 움직임·신호·탐지를 재현합니다. 영상은 실제 경로와 동일한 H.264/RTSP 파이프라인을 별도로 실행합니다.

```bash
cd server
DRONE_SERVER_URL=http://localhost:8001 python3 -u scenario.py

# MediaMTX 실행 후, 카메라 없는 개발 PC에서 H.264 테스트 영상 송출
python3 pi/mock_video_stream.py --url rtsp://localhost:8554/drone
```

강남역에서 출발해서 신논현역 6번 출구까지 10초 정도 이동하며 신호가 점점 강해지고, 도착하면 요구조자 탐지 이벤트가 뜬 뒤 그 자리에서 호버링합니다.

### 6. 라즈베리파이 게이트웨이 (실제 하드웨어 연동)

`scenario.py`/`dummy.py` 대신 실제 H743·RTL-SDR·FPGA로 telemetry·signal·detection을 보내고 싶을 때 씁니다.
서버가 켜진 상태에서, 라즈베리파이 또는 다른 터미널에서:

```bash
cd pi/gateway
pip install -r requirements.txt

# 하드웨어 없이 먼저 파이프라인만 확인 — 강남역→신논현역 접근 시나리오를 재현해서
# RSS가 세지다가 rss_threshold 탐지가 실제로 트리거되는 것까지 볼 수 있음
INPUT_MODE=mock DETECTION_MODE=rss_threshold SERVER_URL=http://localhost:8001 python3 main.py
```

실제 하드웨어 파이프라인은 H743 MAVLink와 RTL-SDR/FPGA를 함께 실행합니다.
SDR 또는 FPGA만 mock으로 두어 구간별로 확인할 수도 있습니다.

```bash
pip install -r requirements-hardware.txt

# 실제 H743 + 실제 RTL-SDR + 실제 FPGA SPI
INPUT_MODE=signal_pipeline SDR_MODE=real FPGA_MODE=real \
  FC_SERIAL_PORT=/dev/serial0 FC_BAUD_RATE=115200 \
  CAMERA_ENABLED=true CAMERA_RTSP_URL=rtsp://SERVER_IP:8554/drone \
  python3 main.py
```

실기 모드에서 Pi는 RSS 임계치를 다시 판단하지 않습니다. FPGA 결과 패킷의 `camera_arm` 비트가
카메라를 미리 켜고 `detected` 비트가 탐지 이벤트를 발생시킵니다. 신호가 약해진 뒤에도 기본
20초 동안 송출을 유지해 카메라 재기동 진동을 줄입니다. 라즈베리파이 측 드라이버와 결과 패킷
계약은 구현되어 있지만, 실제 연결에는 FPGA RTL의 SPI slave·READY·결과 직렬화 구현이 필요합니다.
자세한 환경변수는 `pi/gateway/README.md` 참고.

## 참고
- 서버는 DB 없이 전부 인메모리로 동작합니다. 재시작하면 상태가 초기화됩니다.
- 현재 관제 UI는 프로젝트 범위에 맞춰 단일 드론 중심으로 구성했습니다. 서버와 앱의 상태 저장 구조는 드론 ID를 유지해 향후 다중 드론 관제로 확장할 수 있습니다.

## H743 비행제어보드 연동

Raspberry Pi는 H743 비행제어보드와 UART로 연결하여 MAVLink 기반의
GPS 위치, 고도, 배터리 및 비행 상태 정보를 수신할 수 있습니다.

`signal_pipeline`은 H743 MAVLink와 RTL-SDR/FPGA를 하나의 실제 하드웨어
파이프라인으로 실행합니다.

```bash
INPUT_MODE=signal_pipeline \
SDR_MODE=real \
FPGA_MODE=real \
FC_SERIAL_PORT=/dev/serial0 \
FC_BAUD_RATE=115200 \
python3 main.py
```

현재 Baud rate는 `115200`으로 설정되어 있습니다.

`FC_SERIAL_PORT=/dev/serial0`은 기본값이며, 실제 Raspberry Pi와 H743를
연결한 후 사용되는 UART 포트를 확인하여 변경해야 합니다.

자세한 설정과 실행 방법은
[`pi/gateway/README.md`](pi/gateway/README.md)를 참고하세요.
