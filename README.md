# drowning — 다중 드론 릴레이 기반 재난 통신망 복구 및 요구조자 관제 시스템

[![CI](https://github.com/v33jy/drowning/actions/workflows/ci.yml/badge.svg)](https://github.com/v33jy/drowning/actions/workflows/ci.yml)

드론이 재난 지역 상공을 돌아다니며 통신 신호를 릴레이하고, 요구조자를 찾아내면 관제 앱에 위치와 영상을 바로 띄워주는 시스템입니다.

## 구조

```
[드론 시뮬레이터]          [FastAPI 서버]           [Flutter 관제 앱]
  scenario.py   ──HTTP──▶  /drones/{id}/telemetry  ──WebSocket──▶  지도·드론 마커
  (위치, RSS)   ──HTTP──▶  /drones/{id}/signal     ──WebSocket──▶  전파 히트맵
                ──HTTP──▶  /detection              ──WebSocket──▶  탐지 알림 팝업
                ──WS(스트림)──▶ /drones/{id}/video  ──WebSocket──▶  팝업 내 영상 프리뷰

[라즈베리파이 (pi/)]      (실제 UART 하드웨어·카메라 연동, 위와 동일한 엔드포인트를 침)
  pi/gateway/main.py      ──HTTP──▶  위와 동일 (telemetry·signal·detection)
  pi/camera_stream.py     ──WS(스트림)──▶  /drones/{id}/video
```

- `server/` — FastAPI 백엔드. 드론 텔레메트리·신호·탐지·영상을 받아서 WebSocket으로 관제 앱에 뿌림
- `app/` — Flutter 관제 앱 (iPad 대상, 가로 고정). 지도 위에 드론 위치, 전파 히트맵, 탐지 팝업, 영상 프리뷰를 보여줌
- `pi/` — 실제 라즈베리파이에 올려서 실행하는 코드. `gateway/`(UART로 받은 드론 패킷을 서버로 전달, `scenario.py`가 가짜 데이터로 대신하는 것과 같은 자리)와 `camera_stream.py`(카메라 영상을 서버로 스트리밍)

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

### 2. 관제 앱

서버가 켜진 상태에서 별도 터미널로:

```bash
cd app
flutter run --device-id {시뮬레이터_또는_기기_ID} \
  --dart-define=SERVER_HOST=localhost \
  --dart-define=HTTP_PORT=8001
```

앱은 켜지자마자 서버에 격자 정보를 요청하고 WebSocket을 연결합니다 — 서버를 먼저 안 켜두면 "Cannot reach server" 화면이 뜹니다.

### 3. 드론 시뮬레이터

데모용 시나리오 스크립트로 드론의 움직임·신호·탐지·영상을 재현합니다. 서버가 켜진 상태에서 또 다른 터미널로:

```bash
cd server
DRONE_SERVER_URL=http://localhost:8001 python3 -u scenario.py
```

강남역에서 출발해서 신논현역 6번 출구까지 30초 정도 이동하며 신호가 점점 강해지고, 도착하면 요구조자 탐지 이벤트가 뜨면서 영상 프레임이 계속 전송되며 그 자리에서 호버링합니다.

### 4. 라즈베리파이 게이트웨이 (실제 하드웨어 연동)

`scenario.py`/`dummy.py` 대신 실제 UART 하드웨어로 telemetry·signal·detection을 보내고 싶을 때 씁니다.
서버가 켜진 상태에서, 라즈베리파이 또는 다른 터미널에서:

```bash
cd pi/gateway
pip install -r requirements.txt

# 하드웨어 없이 먼저 파이프라인만 확인 — 강남역→신논현역 접근 시나리오를 재현해서
# RSS가 세지다가 rss_threshold 탐지가 실제로 트리거되는 것까지 볼 수 있음
INPUT_MODE=mock DETECTION_MODE=rss_threshold SERVER_URL=http://localhost:8001 python3 main.py
```

실제 UART 장치를 붙일 땐 `INPUT_MODE=serial`로, 패킷 포맷이 맞는지 먼저 확인하고 싶으면
`INPUT_MODE=raw_debug`로 실행하면 됩니다. 시리얼 연결이 끊겨도 자동으로 재연결을 시도합니다.

RTL-SDR과 FPGA 신호처리 파이프라인은 다음처럼 실행합니다. SDR 또는 FPGA만 mock으로 두어
구간별로 확인할 수도 있습니다.

```bash
pip install -r requirements-hardware.txt

# 전체 mock
INPUT_MODE=signal_pipeline SDR_MODE=mock FPGA_MODE=mock \
  DETECTION_MODE=rss_threshold python3 main.py

# 실제 RTL-SDR + 실제 FPGA SPI
INPUT_MODE=signal_pipeline SDR_MODE=real FPGA_MODE=real \
  DETECTION_MODE=rss_threshold python3 main.py
```

라즈베리파이 측 RTL-SDR 및 SPI 드라이버는 구현되어 있습니다. 다만 실제 연결에는 FPGA RTL의
SPI slave와 연산 완료 READY 처리가 추가로 필요합니다.
자세한 환경변수는 `pi/gateway/README.md` 참고.

카메라 영상을 같이 스트리밍하려면 라즈베리파이에서 별도 터미널로:

```bash
cd pi
pip install -r requirements-camera.txt picamera2
python3 camera_stream.py --drone-id 1 --fps 12

# 카메라/라즈베리파이 없이 나머지 파이프라인만 확인하려면
python3 camera_stream.py --mock --drone-id 1
```

## 참고
- 서버는 DB 없이 전부 인메모리로 동작합니다. 재시작하면 상태가 초기화됩니다.
