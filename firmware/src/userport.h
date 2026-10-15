// userport.h - the WiC64 transfer protocol on the C64's user port
//
// The wiring of the WiC64 (ESP32 pin numbers):
//   PB0-PB7  data          16, 17, 18, 19, 21, 22, 23, 25
//   PC2      C64 -> ESP    14   strobed low by each read or write of $DD01
//   PA2      direction     27   high: the C64 sends, low: it receives
//   FLAG2    ESP -> C64    26   pulsed low to answer each byte
//
// A request ('R' cmd size(2) payload, or 'E' cmd size(4) payload) is
// read byte by byte in the interrupt routine; when it is complete, the
// main loop takes it with Userport::request(), and answers it with
// Userport::respond(), which waits for the C64 to turn the port round.

#pragma once
#include <Arduino.h>
#include <algorithm>

namespace Userport {
    // The buffer the request arrives in and the response is built in:
    // header (up to 6 bytes) and payload
    const size_t BUFFER_SIZE = 65536 + 8;
    extern uint8_t *buffer;

    void begin();

    // A complete request?  Then protocol ('R' or 'E'), command, the
    // payload (in buffer) and its size
    bool request(uint8_t &protocol, uint8_t &command, uint8_t *&payload, uint32_t &size);

    // Answer the request taken: status and size bytes of payload, which
    // the caller has put at response_payload() (at most response_max()
    // bytes; it overlaps the request's payload)
    uint8_t *response_payload();
    uint32_t response_max();
    void respond(uint8_t status, uint32_t size);

    // The same as a burst: no FLAG2 for each byte, the C64 reads back to
    // back.  At most BURST_MAX bytes of payload; it gives up if the C64
    // stops reading for BURST_TIMEOUT_US.
    const uint32_t BURST_MAX = 12000;
    const uint32_t BURST_TIMEOUT_US = 50000;
    void respond_burst(uint8_t status, uint32_t size);

    // Called often from the main loop: gives up on stalled transfers,
    // and lights the LED while busy
    void poll();
}
