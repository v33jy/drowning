# drowning — 다중 드론 릴레이 기반 재난 통신망 복구 및 요구조자 관제 시스템

드론이 재난 지역 상공을 돌아다니며 통신 신호를 릴레이하고, 요구조자를 찾아내면 관제 앱에 위치와 영상, 음성 통화 채널을 바로 띄워주는 시스템입니다.

## 구조

```
[드론 시뮬레이터]          [FastAPI 서버]           [Flutter 관제 앱]
  scenario.py   ──HTTP──▶  /drones/{id}/telemetry  ──WebSocket──▶  지도·드론 마커
  (위치, RSS)   ──HTTP──▶  /drones/{id}/signal     ──WebSocket──▶  전파 히트맵
                ──HTTP──▶  /detection              ──WebSocket──▶  탐지 알림 팝업
                ──HTTP──▶  /drones/{id}/video      ──WebSocket──▶  팝업 내 영상 프리뷰
                              │
                     [VoIP UDP 릴레이 :5005]
                         SURVIVOR ◀──────────────────────────────▶ CONTROL
                       scenario.py                              Flutter 앱
```

- `server/` — FastAPI 백엔드. 드론 텔레메트리·신호·탐지·영상을 받아서 WebSocket으로 관제 앱에 뿌리고, 음성 통화는 UDP로 직접 중계함
- `app/` — Flutter 관제 앱 (iPad 대상, 가로 고정). 지도 위에 드론 위치, 전파 히트맵, 탐지 팝업, 영상 프리뷰, 음성 통화 버튼을 보여줌

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

데모용 시나리오 스크립트로 드론의 움직임·신호·탐지·음성·영상을 재현합니다. 서버가 켜진 상태에서 또 다른 터미널로:

```bash
cd server
DRONE_SERVER_URL=http://localhost:8001 python3 -u scenario.py
```

강남역에서 출발해서 신논현역 6번 출구까지 30초 정도 이동하며 신호가 점점 강해지고, 도착하면 요구조자 탐지 이벤트가 뜨면서 TTS로 만든 음성이 VoIP로 전송되고, 이후 영상 프레임도 계속 전송되며 그 자리에서 호버링합니다.

## 참고
- 서버는 DB 없이 전부 인메모리로 동작합니다. 재시작하면 상태가 초기화됩니다.
