#include <Arduino.h>
#include <LoRaWan_APP.h>
#include <string.h>
#include <stdlib.h>

// =====================================================
// 드론용 Heltec WiFi LoRa 32 V3
// Basys 3 JA1(PMOD_TX) -> GPIO4 UART RX
// FPGA DET 결과 -> LoRa 910 MHz -> 지상 ESP32
//
// 현장용 변경점
// 1) USB 가짜 DET 입력 비활성화
// 2) 오래된 FIFO를 쌓지 않고 "최신 대기 결과 1개"만 유지
// 3) ACK 재시도 횟수/시간 제한 -> 링크 장애 후 오래된 데이터 폭주 방지
// 4) FPGA DET 패킷 형식 검증 후에만 무선 전송
// =====================================================

#define RESULT_RF_FREQUENCY          910000000
#define TX_OUTPUT_POWER              5
#define LORA_BANDWIDTH               0   // 125 kHz
#define LORA_SPREADING_FACTOR        7
#define LORA_CODINGRATE              1   // 4/5
#define LORA_PREAMBLE_LENGTH         8
#define LORA_SYMBOL_TIMEOUT          0
#define LORA_FIX_LENGTH_PAYLOAD_ON   false
#define LORA_IQ_INVERSION_ON         false

static RadioEvents_t RadioEvents;

constexpr bool DEBUG_LOG = true;
constexpr bool ALLOW_USB_TEST_INPUT = false;  // 실제 운용에서는 반드시 false

#define DBG_PRINT(x)   do { if (DEBUG_LOG) Serial.print(x); } while (0)
#define DBG_PRINTLN(x) do { if (DEBUG_LOG) Serial.println(x); } while (0)

// FPGA JA1(PMOD_TX) -> Heltec GPIO4
HardwareSerial FpgaUart(1);
constexpr int FPGA_RX_PIN = 4;
constexpr uint32_t UART_BAUD_RATE = 115200;

constexpr size_t MAX_MESSAGE_LENGTH = 180;
constexpr size_t MAX_RADIO_PACKET_LENGTH = 240;
constexpr size_t RADIO_RX_BUFFER_SIZE = 256;

// 링크 신뢰성 설정
constexpr uint32_t ACK_TIMEOUT_MS = 350;
constexpr uint32_t RETRY_INTERVAL_MS = 100;
constexpr uint8_t MAX_RETRY_COUNT = 6;
constexpr uint32_t MAX_CURRENT_MESSAGE_AGE_MS = 2200;

struct InputLine {
    char data[MAX_MESSAGE_LENGTH + 1];
    size_t length;
    bool overflow;
};

InputLine usbInput = {{0}, 0, false};
InputLine fpgaInput = {{0}, 0, false};

// 오래된 결과를 FIFO로 쌓지 않고 최신 대기 결과만 보존합니다.
char pendingPayload[MAX_MESSAGE_LENGTH + 1] = {0};
bool pendingPayloadValid = false;

char currentPayload[MAX_MESSAGE_LENGTH + 1] = {0};
char txPacket[MAX_RADIO_PACKET_LENGTH + 1] = {0};
char radioRxPacket[RADIO_RX_BUFFER_SIZE] = {0};

bool currentMessageActive = false;
uint32_t sessionId = 0;
uint32_t currentSequence = 1;
uint8_t currentAttempt = 0;
uint32_t currentMessageStartedAt = 0;
uint32_t ackWaitStartedAt = 0;
uint32_t retryAt = 0;

volatile bool txDoneEvent = false;
volatile bool txTimeoutEvent = false;
volatile bool rxDoneEvent = false;
volatile bool rxTimeoutEvent = false;
volatile bool rxErrorEvent = false;

int16_t radioRxRssi = 0;
int8_t radioRxSnr = 0;

enum class LinkState : uint8_t {
    IDLE,
    TRANSMITTING,
    WAITING_ACK,
    RETRY_WAIT
};

LinkState linkState = LinkState::IDLE;

bool timeReached(uint32_t targetTime) {
    return static_cast<int32_t>(millis() - targetTime) >= 0;
}

// FPGA 출력 형식: DET,<0|1>,<bin 0..1023>,<magnitude>
bool isValidDetMessage(const char* message) {
    if (strncmp(message, "DET,", 4) != 0) return false;

    const char* p = message + 4;
    if ((*p != '0' && *p != '1') || p[1] != ',') return false;

    p += 2;
    char* end = nullptr;
    unsigned long bin = strtoul(p, &end, 10);
    if (end == p || *end != ',' || bin > 1023UL) return false;

    p = end + 1;
    (void)strtoul(p, &end, 10);
    if (end == p || *end != '\0') return false;

    return true;
}

// 새 결과가 오면 아직 전송되지 않은 대기 결과를 최신값으로 교체합니다.
bool storeLatestMessage(const char* message, const char* source) {
    if (!isValidDetMessage(message)) {
        DBG_PRINT("[DROP INVALID ");
        DBG_PRINT(source);
        DBG_PRINT("] ");
        DBG_PRINTLN(message);
        return false;
    }

    strncpy(pendingPayload, message, MAX_MESSAGE_LENGTH);
    pendingPayload[MAX_MESSAGE_LENGTH] = '\0';
    pendingPayloadValid = true;

    DBG_PRINT("[LATEST ");
    DBG_PRINT(source);
    DBG_PRINT("] ");
    DBG_PRINTLN(message);
    return true;
}

void readMessages(Stream& input, InputLine& lineBuffer, const char* source) {
    while (input.available() > 0) {
        char c = static_cast<char>(input.read());

        if (c == '\r') continue;

        if (c == '\n') {
            if (lineBuffer.overflow) {
                DBG_PRINT("[OVERFLOW ");
                DBG_PRINT(source);
                DBG_PRINTLN("] line dropped");
            } else if (lineBuffer.length > 0) {
                lineBuffer.data[lineBuffer.length] = '\0';
                storeLatestMessage(lineBuffer.data, source);
            }

            lineBuffer.length = 0;
            lineBuffer.overflow = false;
            lineBuffer.data[0] = '\0';
            continue;
        }

        if (!lineBuffer.overflow) {
            if (lineBuffer.length < MAX_MESSAGE_LENGTH) {
                lineBuffer.data[lineBuffer.length++] = c;
            } else {
                lineBuffer.overflow = true;
            }
        }
    }
}

bool parseAckPacket(const char* packet, uint32_t& ackSession, uint32_t& ackSequence) {
    constexpr char PREFIX[] = "ACK,";
    if (strncmp(packet, PREFIX, sizeof(PREFIX) - 1) != 0) return false;

    const char* cursor = packet + sizeof(PREFIX) - 1;
    char* end = nullptr;

    unsigned long parsedSession = strtoul(cursor, &end, 16);
    if (end == cursor || *end != ',') return false;

    cursor = end + 1;
    unsigned long parsedSequence = strtoul(cursor, &end, 10);
    if (end == cursor || *end != '\0') return false;

    ackSession = static_cast<uint32_t>(parsedSession);
    ackSequence = static_cast<uint32_t>(parsedSequence);
    return true;
}

bool buildCurrentPacket() {
    int written = snprintf(
        txPacket,
        sizeof(txPacket),
        "DATA,%08lX,%lu,%s",
        static_cast<unsigned long>(sessionId),
        static_cast<unsigned long>(currentSequence),
        currentPayload
    );

    return written > 0 && written < static_cast<int>(sizeof(txPacket));
}

void finishCurrentMessage(bool delivered, const char* reason) {
    Radio.Sleep();

    if (delivered) {
        DBG_PRINT("[DELIVERED] SEQ=");
        DBG_PRINT(currentSequence);
        DBG_PRINT(" ATTEMPTS=");
        DBG_PRINTLN(currentAttempt);
    } else {
        DBG_PRINT("[DROP CURRENT] ");
        DBG_PRINT(reason);
        DBG_PRINT(" SEQ=");
        DBG_PRINTLN(currentSequence);
    }

    currentMessageActive = false;
    currentAttempt = 0;
    linkState = LinkState::IDLE;
    currentSequence++;
    if (currentSequence == 0) currentSequence = 1;
}

void sendCurrentPacket() {
    if (!currentMessageActive) return;

    if (millis() - currentMessageStartedAt >= MAX_CURRENT_MESSAGE_AGE_MS) {
        finishCurrentMessage(false, "STALE");
        return;
    }

    if (currentAttempt >= MAX_RETRY_COUNT) {
        finishCurrentMessage(false, "MAX RETRY");
        return;
    }

    currentAttempt++;
    linkState = LinkState::TRANSMITTING;
    Radio.Sleep();
    Radio.SetChannel(RESULT_RF_FREQUENCY);

    DBG_PRINT("[910 TX #");
    DBG_PRINT(currentAttempt);
    DBG_PRINT("] ");
    DBG_PRINTLN(txPacket);

    Radio.Send(
        reinterpret_cast<uint8_t*>(txPacket),
        static_cast<uint16_t>(strlen(txPacket))
    );
}

void startAckReceive() {
    ackWaitStartedAt = millis();
    linkState = LinkState::WAITING_ACK;
    Radio.Sleep();
    Radio.SetChannel(RESULT_RF_FREQUENCY);
    Radio.Rx(0);
}

void scheduleRetry(const char* reason) {
    Radio.Sleep();

    if (!currentMessageActive) {
        linkState = LinkState::IDLE;
        return;
    }

    if (millis() - currentMessageStartedAt >= MAX_CURRENT_MESSAGE_AGE_MS) {
        finishCurrentMessage(false, "STALE WHILE RETRY");
        return;
    }

    DBG_PRINT("[RETRY] ");
    DBG_PRINTLN(reason);
    retryAt = millis() + RETRY_INTERVAL_MS;
    linkState = LinkState::RETRY_WAIT;
}

void loadLatestMessage() {
    if (currentMessageActive || !pendingPayloadValid) return;

    strncpy(currentPayload, pendingPayload, MAX_MESSAGE_LENGTH);
    currentPayload[MAX_MESSAGE_LENGTH] = '\0';
    pendingPayloadValid = false;

    currentMessageActive = true;
    currentAttempt = 0;
    currentMessageStartedAt = millis();

    if (!buildCurrentPacket()) {
        finishCurrentMessage(false, "PACKET BUILD");
        return;
    }

    sendCurrentPacket();
}

void OnTxDone() { txDoneEvent = true; }
void OnTxTimeout() { txTimeoutEvent = true; }

void OnRxDone(uint8_t* payload, uint16_t size, int16_t rssi, int8_t snr) {
    if (size >= sizeof(radioRxPacket)) size = sizeof(radioRxPacket) - 1;
    memcpy(radioRxPacket, payload, size);
    radioRxPacket[size] = '\0';
    radioRxRssi = rssi;
    radioRxSnr = snr;
    Radio.Sleep();
    rxDoneEvent = true;
}

void OnRxTimeout() { rxTimeoutEvent = true; }
void OnRxError() { rxErrorEvent = true; }

void processRadioEvents() {
    if (txDoneEvent) {
        txDoneEvent = false;
        if (linkState == LinkState::TRANSMITTING) startAckReceive();
    }

    if (txTimeoutEvent) {
        txTimeoutEvent = false;
        if (linkState == LinkState::TRANSMITTING) scheduleRetry("TX TIMEOUT");
    }

    if (rxDoneEvent) {
        rxDoneEvent = false;
        if (linkState == LinkState::WAITING_ACK) {
            uint32_t ackSession = 0;
            uint32_t ackSequence = 0;
            bool valid = parseAckPacket(radioRxPacket, ackSession, ackSequence);

            DBG_PRINT("[910 RX ACK] ");
            DBG_PRINT(radioRxPacket);
            DBG_PRINT(" RSSI=");
            DBG_PRINT(radioRxRssi);
            DBG_PRINT(" SNR=");
            DBG_PRINTLN(radioRxSnr);

            if (valid && ackSession == sessionId && ackSequence == currentSequence) {
                finishCurrentMessage(true, "ACK");
            } else if (millis() - ackWaitStartedAt < ACK_TIMEOUT_MS) {
                Radio.SetChannel(RESULT_RF_FREQUENCY);
                Radio.Rx(0);
            } else {
                scheduleRetry("ACK MISMATCH");
            }
        }
    }

    if (rxTimeoutEvent) {
        rxTimeoutEvent = false;
        if (linkState == LinkState::WAITING_ACK) scheduleRetry("RX TIMEOUT");
    }

    if (rxErrorEvent) {
        rxErrorEvent = false;
        if (linkState == LinkState::WAITING_ACK) scheduleRetry("RX ERROR");
    }
}

void setup() {
    Serial.begin(115200);
    delay(1200);

    // FPGA UART는 RX만 사용합니다.
    FpgaUart.begin(UART_BAUD_RATE, SERIAL_8N1, FPGA_RX_PIN, -1);

    Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

    sessionId = esp_random();
    if (sessionId == 0) sessionId = 1;

    RadioEvents.TxDone = OnTxDone;
    RadioEvents.TxTimeout = OnTxTimeout;
    RadioEvents.RxDone = OnRxDone;
    RadioEvents.RxTimeout = OnRxTimeout;
    RadioEvents.RxError = OnRxError;

    Radio.Init(&RadioEvents);
    Radio.SetChannel(RESULT_RF_FREQUENCY);

    Radio.SetTxConfig(
        MODEM_LORA, TX_OUTPUT_POWER, 0,
        LORA_BANDWIDTH, LORA_SPREADING_FACTOR, LORA_CODINGRATE,
        LORA_PREAMBLE_LENGTH, LORA_FIX_LENGTH_PAYLOAD_ON,
        true, 0, 0, LORA_IQ_INVERSION_ON, 3000
    );

    Radio.SetRxConfig(
        MODEM_LORA,
        LORA_BANDWIDTH, LORA_SPREADING_FACTOR, LORA_CODINGRATE,
        0, LORA_PREAMBLE_LENGTH, LORA_SYMBOL_TIMEOUT,
        LORA_FIX_LENGTH_PAYLOAD_ON, 0,
        true, 0, 0, LORA_IQ_INVERSION_ON, true
    );

    DBG_PRINTLN("# DRONE FIELD SENDER READY: FPGA UART -> 910 MHz");
    DBG_PRINTLN("# FPGA UART: GPIO4 / 115200 8N1");
    DBG_PRINTLN("# USB TEST INPUT: DISABLED");
}

void loop() {
    Radio.IrqProcess();
    processRadioEvents();

    // 실제 경로: FPGA -> GPIO4 UART
    readMessages(FpgaUart, fpgaInput, "FPGA");

    // 소스코드에서 명시적으로 true로 바꿨을 때만 USB 테스트 입력 사용
    if (ALLOW_USB_TEST_INPUT) {
        readMessages(Serial, usbInput, "USB");
    }

    if (currentMessageActive &&
        millis() - currentMessageStartedAt >= MAX_CURRENT_MESSAGE_AGE_MS) {
        finishCurrentMessage(false, "STALE WATCHDOG");
    }

    if (linkState == LinkState::WAITING_ACK &&
        millis() - ackWaitStartedAt >= ACK_TIMEOUT_MS) {
        scheduleRetry("ACK TIMEOUT");
    }

    if (linkState == LinkState::RETRY_WAIT && timeReached(retryAt)) {
        sendCurrentPacket();
    }

    if (linkState == LinkState::IDLE) {
        loadLatestMessage();
    }
}
