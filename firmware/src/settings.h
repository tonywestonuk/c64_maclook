// settings.h - what is set up on the web page, kept in the ESP32's NVS

#pragma once
#include <Arduino.h>
#include <vector>

struct ShareSettings {
    String name;        // as the C64 shows it
    String server;      // host name or IP address
    String share;       // the share's name on the server
    String user;        // empty: guest
    String password;
    String domain;      // usually empty (or the workgroup)
};

namespace Settings {
    const int MAX_SHARES = 6;

    extern String wifi_ssid;
    extern String wifi_password;
    extern String hostname;
    extern String flash_name;   // the name of volume 0
    extern String timezone;     // POSIX TZ, for file dates
    extern std::vector<ShareSettings> shares;

    void load();
    void save();
}
