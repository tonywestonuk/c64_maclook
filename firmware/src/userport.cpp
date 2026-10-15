// userport.cpp - the WiC64 transfer protocol on the C64's user port
//
// As the WiC64's own firmware does it: every byte the C64 writes to
// $DD01 is acknowledged on FLAG2; when the response is ready and the C64
// has turned the port round (PA2 low), one FLAG2 pulse says so; then
// every read of $DD01 (a PC2 strobe) is answered with the next byte and
// a FLAG2 pulse.  A request that arrives while the last one is still
// being worked on is not acknowledged: the C64 sees a timeout.
//
// A burst (respond_burst) skips the FLAG2 for each byte: the C64 reads
// $DD01 back to back, and the next byte must be on the port before its
// next read, a few microseconds later.  The interrupt is too slow for
// that, so a burst is sent from a loop that watches PC2's edge latch.

#include "userport.h"
#include "soc/gpio_struct.h"
#include "rom/ets_sys.h"
#include "driver/gpio.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

namespace Userport {

uint8_t *buffer = nullptr;

static const int PIN_PC2 = 14;
static const int PIN_PA2 = 27;
static const int PIN_FLAG2 = 26;
static const int PIN_LED = 2;
static const int DATA_PINS[8] = {16, 17, 18, 19, 21, 22, 23, 25};
static const uint32_t PORT_MASK =
    (0x0fUL << 16) |    // PB0-PB3: 16-19
    (0x07UL << 21) |    // PB4-PB6: 21-23
    (0x01UL << 25);     // PB7:     25

enum State {
    IDLE,
    RECEIVING,          // a request is coming in
    REQUEST_READY,      // it is complete, for the main loop
    PROCESSING,         // the main loop is working on it
    RESPONSE_READY,     // the response waits for PA2 low
    TURNING,            // FLAG2 sent: the C64's next read starts it
    SENDING,
    BURST,              // respond_burst has the port
};
static volatile State state = IDLE;
static volatile uint32_t pos = 0;           // receiving: bytes so far
static volatile uint32_t expected = 0;      // receiving: total (0 = header incomplete)
static volatile uint32_t send_pos = 0;      // sending: next byte
static volatile uint32_t send_size = 0;
static volatile uint32_t last_activity = 0;
static volatile uint8_t header_size = 4;
static portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;

static inline uint8_t IRAM_ATTR read_port()
{
    uint32_t in = GPIO.in;
    return ((in >> 16) & 0x0f) | ((in >> 17) & 0x70) | ((in >> 18) & 0x80);
}

static inline void IRAM_ATTR write_port(uint8_t b)
{
    uint32_t set = ((uint32_t)(b & 0x0f) << 16) | ((uint32_t)(b & 0x70) << 17) | ((uint32_t)(b & 0x80) << 18);
    GPIO.out_w1ts = set;
    GPIO.out_w1tc = PORT_MASK & ~set;
}

static inline void IRAM_ATTR port_output() { GPIO.enable_w1ts = PORT_MASK; }
static inline void IRAM_ATTR port_input() { GPIO.enable_w1tc = PORT_MASK; }
static inline bool IRAM_ATTR pa2_high() { return (GPIO.in >> PIN_PA2) & 1; }

static inline void IRAM_ATTR flag2()
{
    GPIO.out_w1tc = 1UL << PIN_FLAG2;
    ets_delay_us(3);
    GPIO.out_w1ts = 1UL << PIN_FLAG2;
}

static inline uint32_t IRAM_ATTR now_ms()
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

// PC2: the C64 has read or written $DD01
static void IRAM_ATTR on_pc2()
{
    portENTER_CRITICAL_ISR(&mux);
    last_activity = now_ms();
    if (pa2_high()) {                       // the C64 is sending
        if (state == RESPONSE_READY || state == TURNING || state == SENDING) {
            port_input();                   // (it gave up on the last response)
            state = IDLE;
        }
        if (state == IDLE) {
            uint8_t b = read_port();
            if (b == 'R' || b == 'E') {
                header_size = b == 'E' ? 6 : 4;
                buffer[0] = b;
                pos = 1;
                expected = 0;
                state = RECEIVING;
                flag2();
            }                               // (anything else: not for us)
        } else if (state == RECEIVING) {
            uint8_t b = read_port();
            if (pos < BUFFER_SIZE) {
                buffer[pos] = b;
            }
            pos++;
            if (expected == 0 && pos == header_size) {
                uint32_t payload = buffer[2] | (buffer[3] << 8);
                if (header_size == 6) {
                    payload |= ((uint32_t)buffer[4] << 16) | ((uint32_t)buffer[5] << 24);
                }
                expected = header_size + payload;
            }
            flag2();
            if (expected && pos >= expected) {
                state = REQUEST_READY;
            }
        }                                   // (busy with the last one: no answer)
    } else {                                // the C64 is receiving
        if (state == TURNING) {             // its first read: "go on"
            port_output();
            write_port(buffer[0]);
            send_pos = 1;
            state = SENDING;
            flag2();
        } else if (state == SENDING) {
            if (send_pos < send_size) {
                write_port(buffer[send_pos++]);
                flag2();
            } else {
                port_input();               // all sent
                state = IDLE;
            }
        }
    }
    portEXIT_CRITICAL_ISR(&mux);
}

// PA2 fell: the C64 has turned round to receive
static void IRAM_ATTR on_pa2()
{
    portENTER_CRITICAL_ISR(&mux);
    if (state == RESPONSE_READY && !pa2_high()) {
        state = TURNING;
        last_activity = now_ms();
        flag2();
    }
    portEXIT_CRITICAL_ISR(&mux);
}

void begin()
{
    buffer = (uint8_t *)malloc(BUFFER_SIZE);
    pinMode(PIN_LED, OUTPUT);
    digitalWrite(PIN_LED, LOW);
    for (int pin : DATA_PINS) {
        pinMode(pin, INPUT);
        digitalWrite(pin, LOW);
    }
    pinMode(PIN_PA2, INPUT);
    pinMode(PIN_PC2, INPUT_PULLUP);
    digitalWrite(PIN_FLAG2, HIGH);
    pinMode(PIN_FLAG2, OUTPUT);
    attachInterrupt(digitalPinToInterrupt(PIN_PC2), on_pc2, FALLING);
    attachInterrupt(digitalPinToInterrupt(PIN_PA2), on_pa2, FALLING);
}

bool request(uint8_t &protocol, uint8_t &command, uint8_t *&payload, uint32_t &size)
{
    if (state != REQUEST_READY) {
        return false;
    }
    portENTER_CRITICAL(&mux);
    state = PROCESSING;
    portEXIT_CRITICAL(&mux);
    protocol = buffer[0];
    command = buffer[1];
    payload = buffer + header_size;
    uint32_t total = expected;
    size = std::min<uint32_t>(total, BUFFER_SIZE) - header_size;
    return true;
}

uint8_t *response_payload()
{
    return buffer + (header_size == 6 ? 5 : 3);
}

uint32_t response_max()
{
    return header_size == 6 ? BUFFER_SIZE - 5 : 0xffff;
}

// The response's header in front of its payload: its whole size
static uint32_t header(uint8_t status, uint32_t size)
{
    buffer[0] = status;
    buffer[1] = size & 0xff;
    buffer[2] = (size >> 8) & 0xff;
    if (header_size == 6) {
        buffer[3] = (size >> 16) & 0xff;
        buffer[4] = (size >> 24) & 0xff;
        return 5 + size;
    }
    return 3 + size;
}

void respond(uint8_t status, uint32_t size)
{
    uint32_t total = header(status, std::min(size, response_max()));
    portENTER_CRITICAL(&mux);
    send_size = total;
    if (state == PROCESSING) {
        last_activity = now_ms();
        if (pa2_high()) {
            state = RESPONSE_READY;         // on_pa2 goes on
        } else {
            state = TURNING;
            flag2();                        // "the response is ready"
        }
    }
    portEXIT_CRITICAL(&mux);
}

void respond_burst(uint8_t status, uint32_t size)
{
    uint32_t total = header(status, std::min(size, BURST_MAX));
    portENTER_CRITICAL(&mux);
    bool ours = state == PROCESSING;
    if (ours) {
        state = BURST;                      // (the interrupts leave the port alone)
    }
    portEXIT_CRITICAL(&mux);
    if (!ours) {
        return;
    }
    digitalWrite(PIN_LED, HIGH);
    uint32_t start = millis();              // the C64 turns the port round
    while (pa2_high()) {
        if (millis() - start > 3000) {
            state = IDLE;
            return;
        }
        delay(1);
    }
    // Nothing else on this core until it's done: PC2's interrupt off (its
    // edges are still latched in GPIO.status), and no task switches
    const uint32_t timeout = ESP.getCpuFreqMHz() * BURST_TIMEOUT_US;
    gpio_intr_disable((gpio_num_t)PIN_PC2);
    vTaskSuspendAll();
    GPIO.status_w1tc = 1UL << PIN_PC2;
    flag2();                                // "ready": the C64's next read starts it
    for (uint32_t i = 0;; i++) {
        uint32_t t0 = ESP.getCycleCount();
        bool strobed = true;
        while (!(GPIO.status & (1UL << PIN_PC2))) {
            if (ESP.getCycleCount() - t0 > timeout) {
                strobed = false;            // the C64 stopped reading
                break;
            }
        }
        GPIO.status_w1tc = 1UL << PIN_PC2;
        if (!strobed || i == total) {       // (the read of the last byte)
            break;
        }
        write_port(buffer[i]);
        if (i == 0) {
            port_output();
        }
    }
    port_input();
    GPIO.status_w1tc = 1UL << PIN_PC2;
    xTaskResumeAll();
    gpio_intr_enable((gpio_num_t)PIN_PC2);
    portENTER_CRITICAL(&mux);
    state = IDLE;
    last_activity = now_ms();
    portEXIT_CRITICAL(&mux);
}

void poll()
{
    State s = state;
    bool active = s == RECEIVING || s == TURNING || s == SENDING;
    digitalWrite(PIN_LED, active || s == PROCESSING ? HIGH : LOW);
    if (active && now_ms() - last_activity > 2000) {
        portENTER_CRITICAL(&mux);
        if (state == s) {                   // stalled: give up
            port_input();
            state = IDLE;
        }
        portEXIT_CRITICAL(&mux);
    }
}

}  // namespace Userport
