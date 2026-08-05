import time

import serial
from serial import SerialException


FPGA_PORT = "COM4"
ESP32_PORT = "COM3"
BAUD_RATE = 115200


def main():
    try:
        fpga = serial.Serial(
            FPGA_PORT,
            BAUD_RATE,
            timeout=0.1,
        )

        esp32 = serial.Serial(
            ESP32_PORT,
            BAUD_RATE,
            timeout=0.1,
        )

    except SerialException as error:
        print("COM 포트를 열 수 없습니다.")
        print(error)
        return

    time.sleep(2)

    print("FPGA -> 노트북 -> ESP32 중계를 시작합니다.")
    print("종료하려면 Ctrl+C를 누르십시오.")

    try:
        while True:
            if fpga.in_waiting > 0:
                data = fpga.readline()

                if data:
                    esp32.write(data)
                    esp32.flush()

                    text = data.decode(
                        "utf-8",
                        errors="replace",
                    ).strip()

                    print("전달 데이터:", text)

            if esp32.in_waiting > 0:
                response = esp32.readline()

                if response:
                    text = response.decode(
                        "utf-8",
                        errors="replace",
                    ).strip()

                    print("ESP32 응답:", text)

            time.sleep(0.01)

    except KeyboardInterrupt:
        print("\n중계를 종료합니다.")

    finally:
        fpga.close()
        esp32.close()


if __name__ == "__main__":
    main()