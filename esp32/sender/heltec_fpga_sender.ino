#include <Arduino.h>
#include <LoRaWan_APP.h>
#include <string.h>

// =====================================================
// LoRa 설정
// 수신기와 모든 값이 같아야 합니다.
// =====================================================

#define RF_FREQUENCY                 915000000
#define TX_OUTPUT_POWER              5
#define LORA_BANDWIDTH               0
#define LORA_SPREADING_FACTOR        7
#define LORA_CODINGRATE              1
#define LORA_PREAMBLE_LENGTH         8
#define LORA_SYMBOL_TIMEOUT          0
#define LORA_FIX_LENGTH_PAYLOAD_ON   false
#define LORA_IQ_INVERSION_ON         false

static RadioEvents_t RadioEvents;


// =====================================================
// 입력 UART 설정
// =====================================================

// USB Serial:
// 현재 노트북 Python 중계 시험용
//
// FpgaUart:
// 나중에 FPGA와 직접 연결할 UART
HardwareSerial FpgaUart(1);

constexpr int FPGA_RX_PIN = 4;
constexpr uint32_t UART_BAUD_RATE = 115200;


// =====================================================
// 메시지 제한 및 큐 설정
// =====================================================

// FPGA가 보내는 한 줄의 최대 길이
constexpr size_t MAX_MESSAGE_LENGTH = 180;

// LoRa 전송 대기열 크기
constexpr uint8_t QUEUE_SIZE = 8;


struct InputLine {
    char data[MAX_MESSAGE_LENGTH + 1];
    size_t length;
    bool overflow;
};


struct QueueItem {
    char data[MAX_MESSAGE_LENGTH + 1];
};


// USB와 FPGA UART는 서로 다른 버퍼 사용
InputLine usbInput = {{0}, 0, false};
InputLine fpgaInput = {{0}, 0, false};

QueueItem messageQueue[QUEUE_SIZE];

uint8_t queueHead = 0;
uint8_t queueTail = 0;
uint8_t queueCount = 0;

// LoRa가 실제로 송신하는 전역 버퍼
char txPacket[MAX_MESSAGE_LENGTH + 1];

volatile bool loraBusy = false;


// =====================================================
// 메시지 큐 함수
// =====================================================

bool enqueueMessage(
    const char* message,
    const char* source
) {
    if (message[0] == '\0') {
        return false;
    }

    if (queueCount >= QUEUE_SIZE) {
        Serial.print("[QUEUE FULL] 데이터 폐기: ");
        Serial.println(message);
        return false;
    }

    strncpy(
        messageQueue[queueTail].data,
        message,
        MAX_MESSAGE_LENGTH
    );

    messageQueue[queueTail]
        .data[MAX_MESSAGE_LENGTH] = '\0';

    queueTail =
        (queueTail + 1) % QUEUE_SIZE;

    queueCount++;

    Serial.print("[QUEUE ");
    Serial.print(source);
    Serial.print("] ");
    Serial.println(message);

    return true;
}


bool dequeueMessage(char* destination) {
    if (queueCount == 0) {
        return false;
    }

    strncpy(
        destination,
        messageQueue[queueHead].data,
        MAX_MESSAGE_LENGTH
    );

    destination[MAX_MESSAGE_LENGTH] = '\0';

    queueHead =
        (queueHead + 1) % QUEUE_SIZE;

    queueCount--;

    return true;
}


// =====================================================
// UART 한 줄 수신 함수
// =====================================================

void readMessages(
    Stream& input,
    InputLine& lineBuffer,
    const char* source
) {
    while (input.available() > 0) {
        char receivedChar =
            static_cast<char>(input.read());

        // CR은 무시
        if (receivedChar == '\r') {
            continue;
        }

        // LF가 들어오면 메시지 한 줄 완료
        if (receivedChar == '\n') {
            if (lineBuffer.overflow) {
                Serial.print("[OVERFLOW ");
                Serial.print(source);
                Serial.println("] 너무 긴 메시지를 폐기했습니다.");
            }
            else if (lineBuffer.length > 0) {
                lineBuffer.data[
                    lineBuffer.length
                ] = '\0';

                enqueueMessage(
                    lineBuffer.data,
                    source
                );
            }

            // 다음 메시지를 위해 초기화
            lineBuffer.length = 0;
            lineBuffer.overflow = false;
            lineBuffer.data[0] = '\0';

            continue;
        }

        // 정상 문자 저장
        if (!lineBuffer.overflow) {
            if (
                lineBuffer.length <
                MAX_MESSAGE_LENGTH
            ) {
                lineBuffer.data[
                    lineBuffer.length
                ] = receivedChar;

                lineBuffer.length++;
            }
            else {
                // 줄바꿈이 올 때까지 해당 메시지를 무시
                lineBuffer.overflow = true;
            }
        }
    }
}


// =====================================================
// LoRa 이벤트 함수
// =====================================================

void OnTxDone() {
    Serial.println("[LORA TX DONE]");

    Radio.Sleep();
    loraBusy = false;
}


void OnTxTimeout() {
    Serial.println("[LORA TX TIMEOUT]");

    Radio.Sleep();
    loraBusy = false;
}


// =====================================================
// LoRa 송신 함수
// =====================================================

void sendNextMessage() {
    if (loraBusy) {
        return;
    }

    if (!dequeueMessage(txPacket)) {
        return;
    }

    size_t packetLength =
        strlen(txPacket);

    if (packetLength == 0) {
        return;
    }

    Serial.print("[LORA TX START] ");
    Serial.println(txPacket);

    loraBusy = true;

    Radio.Send(
        reinterpret_cast<uint8_t*>(txPacket),
        packetLength
    );
}


// =====================================================
// 초기화
// =====================================================

void setup() {
    // USB Serial:
    // 노트북 시험 입력 및 디버깅 출력
    Serial.begin(115200);
    delay(1500);

    // FPGA 직접 연결용 UART
    // GPIO4를 RX로 사용하고 TX는 사용하지 않음
    FpgaUart.begin(
        UART_BAUD_RATE,
        SERIAL_8N1,
        FPGA_RX_PIN,
        -1
    );

    Mcu.begin(
        HELTEC_BOARD,
        SLOW_CLK_TPYE
    );

    RadioEvents.TxDone = OnTxDone;
    RadioEvents.TxTimeout = OnTxTimeout;

    Radio.Init(&RadioEvents);
    Radio.SetChannel(RF_FREQUENCY);

    Radio.SetTxConfig(
        MODEM_LORA,
        TX_OUTPUT_POWER,
        0,
        LORA_BANDWIDTH,
        LORA_SPREADING_FACTOR,
        LORA_CODINGRATE,
        LORA_PREAMBLE_LENGTH,
        LORA_FIX_LENGTH_PAYLOAD_ON,
        true,
        0,
        0,
        LORA_IQ_INVERSION_ON,
        3000
    );

    Serial.println();
    Serial.println("UNIVERSAL FPGA LORA SENDER READY");
    Serial.println("USB Serial input: READY");
    Serial.println("FPGA UART GPIO4 input: READY");
}


// =====================================================
// 반복 실행
// =====================================================

void loop() {
    Radio.IrqProcess();

    // 현재 노트북 시험 데이터 수신
    readMessages(
        Serial,
        usbInput,
        "USB"
    );

    // 최종 FPGA 직접 연결 데이터 수신
    readMessages(
        FpgaUart,
        fpgaInput,
        "FPGA"
    );

    // 큐에 저장된 메시지를 순서대로 LoRa 송신
    sendNextMessage();
}