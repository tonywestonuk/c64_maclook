// settings.cpp - what is set up on the web page, kept in the ESP32's NVS

#include "settings.h"
#include <Preferences.h>

namespace Settings {

String wifi_ssid;
String wifi_password;
String hostname;
String flash_name;
String timezone;
std::vector<ShareSettings> shares;

static Preferences prefs;

void load()
{
    prefs.begin("desktop64", true);
    wifi_ssid = prefs.getString("ssid", "");
    wifi_password = prefs.getString("pass", "");
    hostname = prefs.getString("host", "wic64");
    flash_name = prefs.getString("flash", "System Disk");
    timezone = prefs.getString("tz", "UTC0");
    shares.clear();
    int n = prefs.getInt("shares", 0);
    for (int i = 0; i < n && i < MAX_SHARES; i++) {
        String k = "s" + String(i);
        ShareSettings s;
        s.name = prefs.getString((k + "name").c_str(), "");
        s.server = prefs.getString((k + "srv").c_str(), "");
        s.share = prefs.getString((k + "shr").c_str(), "");
        s.user = prefs.getString((k + "usr").c_str(), "");
        s.password = prefs.getString((k + "pwd").c_str(), "");
        s.domain = prefs.getString((k + "dom").c_str(), "");
        shares.push_back(s);
    }
    prefs.end();
}

void save()
{
    prefs.begin("desktop64", false);
    prefs.clear();
    prefs.putString("ssid", wifi_ssid);
    prefs.putString("pass", wifi_password);
    prefs.putString("host", hostname);
    prefs.putString("flash", flash_name);
    prefs.putString("tz", timezone);
    prefs.putInt("shares", shares.size());
    for (size_t i = 0; i < shares.size(); i++) {
        String k = "s" + String(i);
        const ShareSettings &s = shares[i];
        prefs.putString((k + "name").c_str(), s.name);
        prefs.putString((k + "srv").c_str(), s.server);
        prefs.putString((k + "shr").c_str(), s.share);
        prefs.putString((k + "usr").c_str(), s.user);
        prefs.putString((k + "pwd").c_str(), s.password);
        prefs.putString((k + "dom").c_str(), s.domain);
    }
    prefs.end();
}

}  // namespace Settings
