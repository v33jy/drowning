#include "Arduino.h"
#include "LoRaWan_APP.h"

#define RF_FREQUENCY                 915000000
#define LORA_BANDWIDTH               0
#define LORA_SPREADING_FACTOR        7
#define LORA_CODINGRATE              1
#define LORA_PREAMBLE_LENGTH         8
#define LORA_SYMBOL_TIMEOUT          0
#define LORA_FIX_LENGTH_PAYLOAD_ON   false
#define LORA_IQ_INVERSION_ON         false

static RadioEvents_t RadioEvents;

char rxPacket[256];

void startReceive() {
    Radio.Rx(0);
}

void OnRxDone(
    uint8_t* payload,
    uint16_t size,
    int16_t rssi,
    int8_t snr
) {
    if (size >= sizeof(rxPacket)) {
        size = sizeof(rxPacket) - 1;
    }

    memcpy(rxPacket, payload, size);
    rxPacket[size] = '\0';

    Serial.print("LORA RX DATA: ");
    Serial.println(rxPacket);

    Serial.print("RSSI: ");
    Serial.println(rssi);

    Serial.print("SNR: ");
    Serial.println(snr);

    startReceive();
}

void OnRxTimeout() {
    Serial.println("LORA RX TIMEOUT");
    startReceive();
}

void OnRxError() {
    Serial.println("LORA RX ERROR");
    startReceive();
}

void setup() {
    Serial.begin(115200);
    delay(1500);

    Mcu.begin(
        HELTEC_BOARD,
        SLOW_CLK_TPYE
    );

    RadioEvents.RxDone = OnRxDone;
    RadioEvents.RxTimeout = OnRxTimeout;
    RadioEvents.RxError = OnRxError;

    Radio.Init(&RadioEvents);
    Radio.SetChannel(RF_FREQUENCY);

    Radio.SetRxConfig(
        MODEM_LORA,
        LORA_BANDWIDTH,
        LORA_SPREADING_FACTOR,
        LORA_CODINGRATE,
        0,
        LORA_PREAMBLE_LENGTH,
        LORA_SYMBOL_TIMEOUT,
        LORA_FIX_LENGTH_PAYLOAD_ON,
        0,
        true,
        0,
        0,
        LORA_IQ_INVERSION_ON,
        true
    );

    Serial.println("LORA RECEIVER READY");

    startReceive();
}

void loop() {
    Radio.IrqProcess();
}