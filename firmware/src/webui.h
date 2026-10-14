// webui.h - Wi-Fi, and the setup page at http://wic64.local/
//
// Without Wi-Fi settings (or if the network cannot be joined, or the
// WiC64's button is held at power-on), the WiC64 opens its own access
// point, "WiC64-Setup", with the page at http://192.168.4.1/.

#pragma once

namespace WebUI {
    void begin();
    void loop();
}
