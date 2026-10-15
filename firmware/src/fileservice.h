// fileservice.h - the C64's requests: a few of the WiC64's standard
// commands, the file service (docs/fileservice.md) and the matrix unit
// (docs/npu.md)

#pragma once
#include <Arduino.h>
#include <vector>
#include "volume.h"

namespace FileService {
    extern std::vector<Volume *> volumes;

    // The matrix unit's command whose response is sent in a burst
    const uint8_t BURST_COMMAND = 0x91;

    // The volumes, from the settings
    void begin();

    // Request cmd with n bytes of payload at p: the response's payload
    // goes to out (at most out_max bytes; out may overlap p, which is
    // read first), its size to out_len.  scratch (scratch_size bytes)
    // is free for copying.  Returns the status.
    uint8_t handle(uint8_t cmd, const uint8_t *p, uint32_t n,
                   uint8_t *out, uint32_t out_max, uint32_t &out_len,
                   uint8_t *scratch, uint32_t scratch_size);

    const String &status_message();
}
