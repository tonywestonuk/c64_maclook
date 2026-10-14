// main.cpp - firmware for a WiC64 that serves the C64 Mac-look desktop
//
// The WiC64 (an ESP32 on the C64's user port) offers the C64 its files
// (docs/fileservice.md): its own flash, the startup disk with the System
// Folder and the applications, and network shares (SMB) as further
// volumes.  Set it up at http://wic64.local/ (see webui.h).
//
// GPL-2.0, like the rest of the project.

#include <Arduino.h>
#include "userport.h"
#include "settings.h"
#include "fileservice.h"
#include "webui.h"

// libsmb2's calls and the web page want more than the default 8K
SET_LOOP_TASK_STACK_SIZE(16 * 1024);

// While copying, the part of the buffer past the request is free
static const uint32_t SCRATCH_OFFSET = 1024;

void setup()
{
    Serial.begin(115200);
    Userport::begin();          // first: the 64K buffer needs a big free block
    if (!Userport::buffer) {
        Serial.println("Not enough memory for the transfer buffer");
    }
    Settings::load();
    FileService::begin();
    WebUI::begin();
    Serial.println("WiC64 desktop64 file service ready");
}

void loop()
{
    uint8_t protocol, command;
    uint8_t *payload;
    uint32_t size;
    if (Userport::buffer && Userport::request(protocol, command, payload, size)) {
        uint32_t out_len = 0;
        uint8_t *scratch = Userport::buffer + SCRATCH_OFFSET;
        uint8_t status = FileService::handle(command, payload, size,
                                             Userport::response_payload(), Userport::response_max(), out_len,
                                             scratch, Userport::BUFFER_SIZE - SCRATCH_OFFSET);
        Userport::respond(status, out_len);
    }
    Userport::poll();
    WebUI::loop();
    delay(0);
}
