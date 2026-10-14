// WiFi.h - the test bench is always "on the network"

#pragma once
#include "Arduino.h"

enum { WL_CONNECTED = 3 };

struct IPAddress {
    String toString() const { return "192.168.1.64"; }
};

struct WiFiClass {
    int status() const { return WL_CONNECTED; }
    IPAddress localIP() const { return {}; }
};

extern WiFiClass WiFi;
