// webui.cpp - Wi-Fi, and the setup page at http://wic64.local/
//
// The page sets the Wi-Fi network, the name of the flash volume, the
// time zone (for file dates) and the network shares; saving restarts
// the WiC64.  A second page lists the flash and takes uploads, so the
// System can be updated without a USB cable.

#include "webui.h"
#include "settings.h"
#include "fileservice.h"
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>
#include <LittleFS.h>

namespace WebUI {

static WebServer server(80);
static bool access_point = false;
static uint32_t restart_at = 0;
static File upload_file;
static String upload_error;

static String html_escape(const String &s)
{
    String out;
    for (size_t i = 0; i < s.length(); i++) {
        char c = s[i];
        if (c == '&') out += "&amp;";
        else if (c == '<') out += "&lt;";
        else if (c == '>') out += "&gt;";
        else if (c == '"') out += "&quot;";
        else out += c;
    }
    return out;
}

static String url_escape(const String &s)
{
    String out;
    const char *hex = "0123456789ABCDEF";
    for (size_t i = 0; i < s.length(); i++) {
        unsigned char c = s[i];
        if (isalnum(c) || c == '-' || c == '_' || c == '.' || c == '/') {
            out += (char)c;
        } else {
            out += '%';
            out += hex[c >> 4];
            out += hex[c & 15];
        }
    }
    return out;
}

static const char STYLE[] PROGMEM = R"(
<meta name="viewport" content="width=device-width, initial-scale=1">
<style>
body { font: 15px/1.4 -apple-system, Helvetica, Arial, sans-serif; margin: 0 auto; max-width: 760px; padding: 16px; color: #111; background: #fff; }
h1 { font-size: 22px; } h2 { font-size: 17px; margin-top: 28px; border-bottom: 2px solid #111; }
label { display: block; margin: 8px 0 2px; font-weight: 600; }
input[type=text], input[type=password] { width: 100%; box-sizing: border-box; padding: 6px; font: inherit; border: 1px solid #111; }
fieldset { border: 1px solid #111; margin: 12px 0; padding: 4px 12px 12px; }
.row { display: grid; grid-template-columns: 1fr 1fr; gap: 0 12px; }
button { font: inherit; padding: 6px 18px; border: 2px solid #111; background: #fff; border-radius: 8px; margin-top: 12px; }
table { border-collapse: collapse; width: 100%; } td, th { text-align: left; padding: 3px 8px; border-bottom: 1px solid #ccc; }
.note { color: #555; font-size: 13px; } nav a { margin-right: 14px; }
</style>
)";

static String page_start(const char *title)
{
    String s = "<!doctype html><html><head><meta charset=\"utf-8\"><title>";
    s += title;
    s += "</title>";
    s += FPSTR(STYLE);
    s += "</head><body><nav><a href=\"/\">Setup</a><a href=\"/files\">Flash</a></nav><h1>";
    s += title;
    s += "</h1>";
    return s;
}

static String field(const char *label, const char *name, const String &value, bool secret = false)
{
    String s = "<label>";
    s += label;
    s += "</label><input type=\"";
    s += secret ? "password" : "text";
    s += "\" name=\"";
    s += name;
    s += "\" value=\"";
    s += secret ? "" : html_escape(value);
    s += "\"";
    if (secret && value.length()) {
        s += " placeholder=\"(unchanged)\"";
    }
    s += ">";
    return s;
}

static void handle_root()
{
    String s = page_start("WiC64 desktop64");
    s += "<p>";
    if (access_point) {
        s += "Not on a network yet: set up the Wi-Fi below.";
    } else {
        s += "On <b>" + html_escape(Settings::wifi_ssid) + "</b> as " + WiFi.localIP().toString();
    }
    s += "</p><table><tr><th>Volume</th><th>Kind</th><th>Status</th></tr>";
    for (size_t i = 0; i < FileService::volumes.size(); i++) {
        Volume *v = FileService::volumes[i];
        s += "<tr><td>" + String(i) + ": " + html_escape(v->name) + "</td><td>";
        s += v->network ? "network share" : "flash";
        s += "</td><td>";
        s += v->connected() ? "connected" : "not connected";
        s += "</td></tr>";
    }
    s += "</table>";

    s += "<form method=\"post\" action=\"/save\"><h2>Wi-Fi</h2><div class=\"row\"><div>";
    s += field("Network (SSID)", "ssid", Settings::wifi_ssid);
    s += "</div><div>";
    s += field("Password", "pass", Settings::wifi_password, true);
    s += "</div></div><h2>The WiC64</h2><div class=\"row\"><div>";
    s += field("Host name (.local)", "host", Settings::hostname);
    s += "</div><div>";
    s += field("Name of the flash volume", "flash", Settings::flash_name);
    s += "</div></div>";
    s += field("Time zone (POSIX TZ, for file dates)", "tz", Settings::timezone);
    s += "<p class=\"note\">For example <code>UTC0</code>, <code>GMT0BST,M3.5.0/1,M10.5.0</code> "
         "(UK), <code>CET-1CEST,M3.5.0,M10.5.0/3</code> (central Europe), "
         "<code>EST5EDT,M3.2.0,M11.1.0</code> (US east).</p>";

    s += "<h2>Network shares</h2><p class=\"note\">Each one is a disk on the C64's desktop. "
         "Server: a host name or IP address (with :port if not 445). Share: its name on the server. "
         "Leave the user empty to log in as a guest. A share with no name is removed.</p>";
    for (int i = 0; i < Settings::MAX_SHARES; i++) {
        ShareSettings sh;
        if (i < (int)Settings::shares.size()) {
            sh = Settings::shares[i];
        }
        String k = "s" + String(i);
        s += "<fieldset><legend>Share " + String(i + 1) + "</legend><div class=\"row\"><div>";
        s += field("Name on the desktop", (k + "name").c_str(), sh.name);
        s += "</div><div>";
        s += field("Server", (k + "srv").c_str(), sh.server);
        s += "</div><div>";
        s += field("Share", (k + "shr").c_str(), sh.share);
        s += "</div><div>";
        s += field("Domain or workgroup", (k + "dom").c_str(), sh.domain);
        s += "</div><div>";
        s += field("User", (k + "usr").c_str(), sh.user);
        s += "</div><div>";
        s += field("Password", (k + "pwd").c_str(), sh.password, true);
        s += "</div></div></fieldset>";
    }
    s += "<button type=\"submit\">Save and restart</button></form></body></html>";
    server.send(200, "text/html", s);
}

static void handle_save()
{
    String ssid = server.arg("ssid");
    if (server.arg("pass").length() || ssid != Settings::wifi_ssid) {
        Settings::wifi_password = server.arg("pass");     // (blank: unchanged)
    }
    Settings::wifi_ssid = ssid;
    String host = server.arg("host");
    Settings::hostname = host.length() ? host : String("wic64");
    String flash = server.arg("flash");
    Settings::flash_name = flash.length() ? flash : String("System Disk");
    String tz = server.arg("tz");
    Settings::timezone = tz.length() ? tz : String("UTC0");

    std::vector<ShareSettings> shares;
    for (int i = 0; i < Settings::MAX_SHARES; i++) {
        String k = "s" + String(i);
        ShareSettings sh;
        sh.name = server.arg(k + "name");
        sh.name.trim();
        if (sh.name.length() == 0) {
            continue;
        }
        sh.server = server.arg(k + "srv");
        sh.share = server.arg(k + "shr");
        sh.user = server.arg(k + "usr");
        sh.domain = server.arg(k + "dom");
        sh.password = server.arg(k + "pwd");
        if (sh.password.length() == 0 && i < (int)Settings::shares.size()) {
            sh.password = Settings::shares[i].password;     // unchanged
        }
        shares.push_back(sh);
    }
    Settings::shares = shares;
    Settings::save();

    String s = page_start("Saved");
    s += "<p>The WiC64 restarts with the new settings. ";
    if (Settings::wifi_ssid.length()) {
        s += "Then find this page at <a href=\"http://" + html_escape(Settings::hostname) + ".local/\">http://" +
             html_escape(Settings::hostname) + ".local/</a> on " + html_escape(Settings::wifi_ssid) + ".";
    }
    s += "</p></body></html>";
    server.send(200, "text/html", s);
    restart_at = millis() + 1500;
}

// The flash: its folders and files, uploads into a folder, new folders,
// deleting.  The folder in hand travels in the URL (?dir=/System Folder,
// none for the top): while a file arrives, only the URL can be read.
static String folder_arg()
{
    String dir = server.arg("dir");
    if (!dir.startsWith("/") || dir.indexOf("..") >= 0) {
        return "";
    }
    while (dir.endsWith("/")) {
        dir = dir.substring(0, dir.length() - 1);
    }
    return dir;
}

static String files_url(const String &dir)
{
    return dir.length() ? "/files?dir=" + url_escape(dir) : String("/files");
}

// A name the C64 can use: printable ASCII, no '/' or ':', not hidden
static bool good_name(const String &name)
{
    if (name.length() == 0 || name.length() > 31 || name[0] == '.') {
        return false;
    }
    for (size_t i = 0; i < name.length(); i++) {
        unsigned char c = name[i];
        if (c < 32 || c > 126 || c == '/' || c == ':') {
            return false;
        }
    }
    return true;
}

static void list_folder(String &s, const String &path, int depth, const String &current)
{
    File dir = LittleFS.open(path.length() ? path : String("/"));
    if (!dir || !dir.isDirectory()) {
        return;
    }
    for (File f = dir.openNextFile(); f; f = dir.openNextFile()) {
        String name = f.name();
        int slash = name.lastIndexOf('/');
        if (slash >= 0) {
            name = name.substring(slash + 1);
        }
        String full = path + "/" + name;
        bool is_dir = f.isDirectory();
        size_t size = f.size();
        f.close();
        s += "<tr><td>";
        for (int i = 0; i < depth; i++) {
            s += "&nbsp;&nbsp;&nbsp;&nbsp;";
        }
        s += html_escape(name);
        if (is_dir) {
            s += full == current ? "/ <b>(here)</b>" : "/ <a href=\"" + files_url(full) + "\">upload here</a>";
        }
        s += "</td><td>";
        if (!is_dir) {
            s += String(size);
        }
        s += "</td><td><a href=\"/delete?path=" + url_escape(full) + (current.length() ? "&dir=" + url_escape(current) : "") +
             "\">delete</a></td></tr>";
        if (is_dir) {
            list_folder(s, full, depth + 1, current);
        }
    }
    dir.close();
}

static void handle_files()
{
    String dir = folder_arg();
    String s = page_start("Flash");
    s += "<p>" + String((LittleFS.totalBytes() - LittleFS.usedBytes()) / 1024) + "K free of " +
         String(LittleFS.totalBytes() / 1024) + "K. Names starting with a dot are hidden from the C64.</p>";
    if (upload_error.length()) {
        s += "<p><b>" + html_escape(upload_error) + "</b></p>";
        upload_error = "";
    }
    s += "<table><tr><th>Name</th><th>Bytes</th><th></th></tr><tr><td>The top";
    s += dir.length() ? " <a href=\"/files\">upload here</a>" : " <b>(here)</b>";
    s += "</td><td></td><td></td></tr>";
    list_folder(s, "", 1, dir);
    String where = dir.length() ? html_escape(dir.substring(1)) : String("the top");
    s += "</table><h2>Upload into " + where + "</h2>";
    s += "<form method=\"post\" action=\"/upload" + (dir.length() ? "?dir=" + url_escape(dir) : String("")) +
         "\" enctype=\"multipart/form-data\"><input type=\"file\" name=\"file\" multiple> "
         "<button type=\"submit\">Upload</button></form>";
    s += "<p class=\"note\">A file of the same name is replaced.</p>";
    s += "<h2>New folder in " + where + "</h2><form method=\"get\" action=\"/mkdir\">";
    s += "<input type=\"hidden\" name=\"dir\" value=\"" + html_escape(dir) + "\">";
    s += field("Name", "name", "");
    s += "<button type=\"submit\">Make it</button></form></body></html>";
    server.send(200, "text/html", s);
}

static void handle_upload_data()
{
    HTTPUpload &up = server.upload();
    if (up.status == UPLOAD_FILE_START) {
        String dir = folder_arg();
        String name = up.filename;
        int slash = name.lastIndexOf('/');
        if (slash >= 0) {
            name = name.substring(slash + 1);
        }
        if (!good_name(name)) {
            upload_error = "Not a name the C64 can use: " + name;
            return;
        }
        if (!LittleFS.exists(dir.length() ? dir : String("/"))) {
            upload_error = "No such folder";
            return;
        }
        upload_file = LittleFS.open(dir + "/" + name, "w");
        if (!upload_file) {
            upload_error = "Cannot write " + name;
        }
    } else if (up.status == UPLOAD_FILE_WRITE) {
        if (upload_file && upload_file.write(up.buf, up.currentSize) != up.currentSize) {
            upload_error = "The flash is full";
            upload_file.close();
        }
    } else if (up.status == UPLOAD_FILE_END || up.status == UPLOAD_FILE_ABORTED) {
        if (upload_file) {
            upload_file.close();
        }
    }
}

static void back_to_files()
{
    server.sendHeader("Location", files_url(folder_arg()));
    server.send(303);
}

static void handle_mkdir()
{
    String name = server.arg("name");
    name.trim();
    String path = folder_arg() + "/" + name;
    if (!good_name(name)) {
        upload_error = "Not a name the C64 can use: " + name;
    } else if (LittleFS.exists(path)) {
        upload_error = "That name is taken";
    } else if (!LittleFS.mkdir(path)) {
        upload_error = "Cannot make the folder";
    }
    back_to_files();
}

static void handle_delete()
{
    String path = server.arg("path");
    if (path.length() > 1 && path.indexOf("..") < 0 && LittleFS.exists(path)) {
        File f = LittleFS.open(path);
        bool dir = f && f.isDirectory();
        f.close();
        if (!(dir ? LittleFS.rmdir(path) : LittleFS.remove(path))) {
            upload_error = dir ? "Only empty folders can be deleted" : "Cannot delete " + path;
        }
    }
    back_to_files();
}

static const int PIN_BUTTON = 33;     // the WiC64's button, high while pressed

void begin()
{
    WiFi.persistent(false);
    pinMode(PIN_BUTTON, INPUT);
    bool setup_wanted = digitalRead(PIN_BUTTON) == HIGH;    // held at power-on
    if (Settings::wifi_ssid.length() && !setup_wanted) {
        WiFi.mode(WIFI_STA);
        WiFi.setHostname(Settings::hostname.c_str());
        WiFi.setAutoReconnect(true);
        WiFi.begin(Settings::wifi_ssid.c_str(), Settings::wifi_password.c_str());
        uint32_t start = millis();
        while (WiFi.status() != WL_CONNECTED && millis() - start < 15000) {
            delay(100);
        }
    }
    if (WiFi.status() == WL_CONNECTED) {
        Serial.printf("On %s as %s\n", Settings::wifi_ssid.c_str(), WiFi.localIP().toString().c_str());
        configTzTime(Settings::timezone.c_str(), "pool.ntp.org", "time.google.com");
    } else {
        WiFi.mode(WIFI_AP);
        WiFi.softAP("WiC64-Setup");
        access_point = true;
        Serial.printf("No network: access point WiC64-Setup, http://%s/\n", WiFi.softAPIP().toString().c_str());
        setenv("TZ", Settings::timezone.c_str(), 1);
        tzset();
    }
    MDNS.begin(Settings::hostname.c_str());
    MDNS.addService("http", "tcp", 80);

    server.on("/", HTTP_GET, handle_root);
    server.on("/save", HTTP_POST, handle_save);
    server.on("/files", HTTP_GET, handle_files);
    server.on("/upload", HTTP_POST, back_to_files, handle_upload_data);
    server.on("/mkdir", HTTP_GET, handle_mkdir);
    server.on("/delete", HTTP_GET, handle_delete);
    server.onNotFound([] { server.send(404, "text/plain", "Not found"); });
    server.begin();
}

void loop()
{
    server.handleClient();
    if (restart_at && (int32_t)(millis() - restart_at) > 0) {
        ESP.restart();
    }
}

}  // namespace WebUI
