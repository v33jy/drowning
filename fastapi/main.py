import threading
import time
from contextlib import asynccontextmanager
from datetime import datetime

import serial
from fastapi import FastAPI


# 수신 ESP32 포트
SERIAL_PORT = "COM5"
BAUD_RATE = 115200

stop_event = threading.Event()

latest_data = {
    "status": "waiting",
    "raw_data": None,
    "detected": None,
    "fft_bin": None,
    "magnitude": None,
    "rssi": None,
    "snr": None,
    "received_at": None,
}


def parse_fpga_data(raw_data: str) -> None:
    """
    예시 데이터:
    DET,1,13,08193
    """

    parts = raw_data.split(",")

    latest_data["raw_data"] = raw_data
    latest_data["received_at"] = datetime.now().isoformat()
    latest_data["status"] = "received"

    if len(parts) == 4 and parts[0] == "DET":
        try:
            latest_data["detected"] = int(parts[1])
            latest_data["fft_bin"] = int(parts[2])
            latest_data["magnitude"] = int(parts[3])
        except ValueError:
            latest_data["status"] = "parse_error"


def serial_reader() -> None:
    while not stop_event.is_set():
        try:
            print(f"[SERIAL] {SERIAL_PORT} 연결 시도")

            with serial.Serial(
                port=SERIAL_PORT,
                baudrate=BAUD_RATE,
                timeout=1,
            ) as receiver:

                # ESP32가 USB 연결 시 재부팅될 수 있으므로 잠시 대기
                time.sleep(2)

                print(f"[SERIAL] {SERIAL_PORT} 연결 완료")

                while not stop_event.is_set():
                    raw_line = receiver.readline()

                    if not raw_line:
                        continue

                    line = raw_line.decode(
                        "utf-8",
                        errors="replace",
                    ).strip()

                    if not line:
                        continue

                    print("[ESP32]", line)

                    if line.startswith("LORA RX DATA:"):
                        data = line.replace(
                            "LORA RX DATA:",
                            "",
                            1,
                        ).strip()

                        parse_fpga_data(data)

                    elif line.startswith("RSSI:"):
                        value = line.replace("RSSI:", "", 1).strip()

                        try:
                            latest_data["rssi"] = int(value)
                        except ValueError:
                            latest_data["rssi"] = value

                    elif line.startswith("SNR:"):
                        value = line.replace("SNR:", "", 1).strip()

                        try:
                            latest_data["snr"] = float(value)
                        except ValueError:
                            latest_data["snr"] = value

        except serial.SerialException as error:
            latest_data["status"] = "serial_error"
            latest_data["error"] = str(error)

            print("[SERIAL ERROR]", error)
            print("[SERIAL] 2초 후 다시 연결합니다.")

            time.sleep(2)


@asynccontextmanager
async def lifespan(app: FastAPI):
    stop_event.clear()

    worker = threading.Thread(
        target=serial_reader,
        daemon=True,
    )
    worker.start()

    yield

    stop_event.set()
    worker.join(timeout=2)


app = FastAPI(
    title="FPGA LoRa FastAPI Server",
    lifespan=lifespan,
)


@app.get("/")
def root():
    return {
        "message": "FastAPI server is running",
        "serial_port": SERIAL_PORT,
    }


@app.get("/telemetry/latest")
def get_latest_data():
    return latest_data