#include <Arduino.h>
#include <LoRaWan_APP.h>
#include <string.h>
#include <stdlib.h>

// =====================================================
// 지상용 Heltec WiFi LoRa 32 V3
// 915 MHz: 요구조자 비콘 역할 송신
// 910 MHz: 드론 ESP32의 FPGA 탐지 결과 수신 + ACK
//
// 한 개의 SX1262를 사용하므로 915 TX와 910 RX는 동시에 수행하지 않고
// 짧은 915 TX 후 즉시 910 RX로 복귀하는 시간분할 방식입니다.
// =====================================================

#define BEACON_RF_FREQUENCY          915000000
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
constexpr bool BEACON_TX_ENABLED = true;

#define DBG_PRINT(x)   do { if (DEBUG_LOG) Serial.print(x); } while (0)
#define DBG_PRINTLN(x) do { if (DEBUG_LOG) Serial.println(x); } while (0)

constexpr size_t RADIO_BUFFER_SIZE = 256;
constexpr size_t ACK_BUFFER_SIZE = 40;
constexpr size_t BEACON_BUFFER_SIZE = 64;

// 비콘은 짧게 송신하고 대부분의 시간은 910 MHz 결과를 수신합니다.
constexpr uint32_t BEACON_INTERVAL_MS = 1000;
constexpr uint32_t ACK_REPLY_DELAY_MS = 70;

char rxPacket[RADIO_BUFFER_SIZE] = {0};
char ackPacket[ACK_BUFFER_SIZE] = {0};
char beaconPacket[BEACON_BUFFER_SIZE] = {0};

volatile bool rxDoneEvent = false;
volatile bool rxTimeoutEvent = false;
volatile bool rxErrorEvent = false;
volatile bool txDoneEvent = false;
volatile bool txTimeoutEvent = false;

int16_t receivedRssi = 0;
int8_t receivedSnr = 0;

bool haveSession = false;
uint32_t activeSession = 0;
uint32_t lastDeliveredSequence = 0;

uint32_t pendingAckSession = 0;
uint32_t pendingAckSequence = 0;
uint32_t ackSendAt = 0;
uint32_t nextBeaconAt = 0;
uint32_t beaconSequence = 1;

enum class GroundState : uint8_t {
    RX_910,
    BEACON_TX_915,
    ACK_DELAY,
    ACK_TX_910
};

GroundState groundState = GroundState::RX_910;

bool timeReached(uint32_t targetTime) {
    return static_cast<int32_t>(millis() - targetTime) >= 0;
}

bool isSequenceNewer(uint32_t sequence, uint32_t reference) {
    // uint32_t wrap-around에도 동작하는 순번 비교
    return static_cast<int32_t>(sequence - reference) > 0;
}

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

void configureChannel(uint32_t frequency) {
    Radio.Sleep();
    Radio.SetChannel(frequency);
}

void startResultReceive() {
    configureChannel(RESULT_RF_FREQUENCY);
    groundState = GroundState::RX_910;
    Radio.Rx(0);
}

bool parseDataPacket(
    const char* packet,
    uint32_t& session,
    uint32_t& sequence,
    const char*& originalData
) {
    constexpr char PREFIX[] = "DATA,";
    if (strncmp(packet, PREFIX, sizeof(PREFIX) - 1) != 0) return false;

    const char* cursor = packet + sizeof(PREFIX) - 1;
    char* end = nullptr;

    unsigned long parsedSession = strtoul(cursor, &end, 16);
    if (end == cursor || *end != ',') return false;

    cursor = end + 1;
    unsigned long parsedSequence = strtoul(cursor, &end, 10);
    if (end == cursor || *end != ',') return false;

    originalData = end + 1;
    if (*originalData == '\0') return false;

    session = static_cast<uint32_t>(parsedSession);
    sequence = static_cast<uint32_t>(parsedSequence);
    return true;
}

void sendBeacon() {
    if (!BEACON_TX_ENABLED) {
        nextBeaconAt = millis() + BEACON_INTERVAL_MS;
        return;
    }

    int written = snprintf(
        beaconPacket,
        sizeof(beaconPacket),
        "RESCUE_BEACON,%lu",
        static_cast<unsigned long>(beaconSequence)
    );

    if (written <= 0 || written >= static_cast<int>(sizeof(beaconPacket))) {
        nextBeaconAt = millis() + BEACON_INTERVAL_MS;
        startResultReceive();
        return;
    }

    beaconSequence++;
    if (beaconSequence == 0) beaconSequence = 1;

    configureChannel(BEACON_RF_FREQUENCY);
    groundState = GroundState::BEACON_TX_915;

    DBG_PRINT("# 915 BEACON TX: ");
    DBG_PRINTLN(beaconPacket);

    Radio.Send(
        reinterpret_cast<uint8_t*>(beaconPacket),
        static_cast<uint16_t>(written)
    );
}

void sendPendingAck() {
    int written = snprintf(
        ackPacket,
        sizeof(ackPacket),
        "ACK,%08lX,%lu",
        static_cast<unsigned long>(pendingAckSession),
        static_cast<unsigned long>(pendingAckSequence)
    );

    if (written <= 0 || written >= static_cast<int>(sizeof(ackPacket))) {
        DBG_PRINTLN("# ACK BUILD ERROR");
        startResultReceive();
        return;
    }

    configureChannel(RESULT_RF_FREQUENCY);
    groundState = GroundState::ACK_TX_910;

    DBG_PRINT("# 910 ACK TX: ");
    DBG_PRINTLN(ackPacket);

    Radio.Send(
        reinterpret_cast<uint8_t*>(ackPacket),
        static_cast<uint16_t>(written)
    );
}

void processReceivedPacket() {
    uint32_t session = 0;
    uint32_t sequence = 0;
    const char* originalData = nullptr;

    if (!parseDataPacket(rxPacket, session, sequence, originalData)) {
        DBG_PRINT("# UNKNOWN 910 PACKET: ");
        DBG_PRINTLN(rxPacket);
        startResultReceive();
        return;
    }

    bool isNewPacket = false;

    if (!haveSession || session != activeSession) {
        haveSession = true;
        activeSession = session;
        lastDeliveredSequence = sequence;
        isNewPacket = true;
    } else if (isSequenceNewer(sequence, lastDeliveredSequence)) {
        lastDeliveredSequence = sequence;
        isNewPacket = true;
    }

    DBG_PRINT("# 910 RX SESSION=");
    if (DEBUG_LOG) Serial.print(session, HEX);
    DBG_PRINT(" SEQ=");
    DBG_PRINT(sequence);
    DBG_PRINT(" RSSI=");
    DBG_PRINT(receivedRssi);
    DBG_PRINT(" SNR=");
    DBG_PRINTLN(receivedSnr);

    if (isNewPacket) {
        if (isValidDetMessage(originalData)) {
            // FastAPI가 읽을 핵심 한 줄. 예: DET,1,0256,0000012345
            Serial.println(originalData);
        } else {
            // 무선 패킷 자체는 받았지만 내용이 깨졌다면 FastAPI로 넘기지 않습니다.
            DBG_PRINT("# DROP INVALID DET: ");
            DBG_PRINTLN(originalData);
        }
    }

    // 유효/중복 여부와 관계없이 정상 DATA 프레임에는 ACK를 보내 재전송 폭주를 막습니다.
    pendingAckSession = session;
    pendingAckSequence = sequence;
    ackSendAt = millis() + ACK_REPLY_DELAY_MS;
    groundState = GroundState::ACK_DELAY;
}

void OnRxDone(uint8_t* payload, uint16_t size, int16_t rssi, int8_t snr) {
    if (size >= sizeof(rxPacket)) size = sizeof(rxPacket) - 1;
    memcpy(rxPacket, payload, size);
    rxPacket[size] = '\0';
    receivedRssi = rssi;
    receivedSnr = snr;
    Radio.Sleep();
    rxDoneEvent = true;
}

void OnRxTimeout() { rxTimeoutEvent = true; }
void OnRxError() { rxErrorEvent = true; }
void OnTxDone() { txDoneEvent = true; }
void OnTxTimeout() { txTimeoutEvent = true; }

void setup() {
    Serial.begin(115200);
    delay(1200);

    Mcu.begin(HELTEC_BOARD, SLOW_CLK_TPYE);

    RadioEvents.RxDone = OnRxDone;
    RadioEvents.RxTimeout = OnRxTimeout;
    RadioEvents.RxError = OnRxError;
    RadioEvents.TxDone = OnTxDone;
    RadioEvents.TxTimeout = OnTxTimeout;

    Radio.Init(&RadioEvents);

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

    DBG_PRINTLN("# GROUND FIELD READY: 915 TX / 910 RX");

    // 부팅 직후 910 MHz 수신을 먼저 연 뒤 첫 비콘을 보냅니다.
    nextBeaconAt = millis() + 500;
    startResultReceive();
}

void loop() {
    Radio.IrqProcess();

    if (rxDoneEvent) {
        rxDoneEvent = false;
        if (groundState == GroundState::RX_910) {
            processReceivedPacket();
        }
    }

    if (txDoneEvent) {
        txDoneEvent = false;

        if (groundState == GroundState::BEACON_TX_915) {
            DBG_PRINTLN("# 915 BEACON TX DONE -> 910 RX");
            nextBeaconAt = millis() + BEACON_INTERVAL_MS;
            startResultReceive();
        } else if (groundState == GroundState::ACK_TX_910) {
            DBG_PRINTLN("# 910 ACK TX DONE -> 910 RX");
            startResultReceive();
        }
    }

    if (txTimeoutEvent) {
        txTimeoutEvent = false;
        DBG_PRINTLN("# TX TIMEOUT -> 910 RX");
        nextBeaconAt = millis() + BEACON_INTERVAL_MS;
        startResultReceive();
    }

    if (rxTimeoutEvent) {
        rxTimeoutEvent = false;
        if (groundState == GroundState::RX_910) startResultReceive();
    }

    if (rxErrorEvent) {
        rxErrorEvent = false;
        if (groundState == GroundState::RX_910) startResultReceive();
    }

    if (groundState == GroundState::ACK_DELAY && timeReached(ackSendAt)) {
        sendPendingAck();
    }

    // ACK가 최우선. ACK 처리 중이 아닐 때만 915 MHz 비콘을 송신합니다.
    if (groundState == GroundState::RX_910 && timeReached(nextBeaconAt)) {
        sendBeacon();
    }
}
