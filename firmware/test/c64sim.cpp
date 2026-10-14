// c64sim.cpp - a test bench for the WiC64 firmware, on the host
//
// The firmware's user port driver, file service and volumes, built with
// stand-ins for the Arduino core (test/shim), serve a simulated C64 that
// talks to them as the System does (src/net.asm): byte by byte over a
// model of the user port lines, waiting for FLAG2 after each one.  The
// flash is a copy of a folder; with --smb host:port/share, volume 1 is
// that SMB share, reached with libsmb2.
//
//   test/run.sh                 builds this and runs it (see there)

#include "Arduino.h"
#include "LittleFS.h"
#include "WiFi.h"
#include "soc/gpio_struct.h"
#include "../src/userport.h"
#include "../src/fileservice.h"
#include "../src/settings.h"

#include <atomic>
#include <chrono>
#include <fstream>
#include <sstream>
#include <thread>
#include <vector>

// ---------------------------------------------------------------------
// The settings (settings.cpp keeps them in NVS)
// ---------------------------------------------------------------------
namespace Settings {
String wifi_ssid = "TestNet";
String wifi_password;
String hostname = "wic64";
String flash_name = "System Disk";
String timezone = "UTC0";
std::vector<ShareSettings> shares;
}

// ---------------------------------------------------------------------
// The user port: the ESP32's pins and the C64's CIA 2
// ---------------------------------------------------------------------
GpioDev GPIO;

static const uint32_t PORT_MASK = (0x0fUL << 16) | (0x07UL << 21) | (0x01UL << 25);
static const int PIN_PC2 = 14, PIN_PA2 = 27, PIN_FLAG2 = 26;

static std::mutex lines;                // the model's state
static uint32_t esp_out = 0, esp_enable = 0;
static uint8_t c64_pb = 0xff;           // $dd01 as written
static bool c64_drives = false;         // $dd03 = $ff
static bool pa2 = true;
static std::atomic<bool> flag_icr(false);       // CIA 2 ICR bit 4
static std::atomic<int> contention(0);  // both sides drove port B
static void (*isr_pc2)() = nullptr;
static void (*isr_pa2)() = nullptr;

static uint8_t esp_byte(uint32_t v)
{
    return ((v >> 16) & 0x0f) | ((v >> 17) & 0x70) | ((v >> 18) & 0x80);
}

static uint32_t port_bits(uint8_t b)
{
    return ((uint32_t)(b & 0x0f) << 16) | ((uint32_t)(b & 0x70) << 17) | ((uint32_t)(b & 0x80) << 18);
}

// What is on port B now (lines held)
static uint8_t port_value()
{
    bool esp = (esp_enable & PORT_MASK) != 0;
    if (esp && c64_drives) {
        contention++;
    }
    if (esp) {
        return esp_byte(esp_out);
    }
    return c64_drives ? c64_pb : 0xff;
}

static void update_in()
{
    uint32_t in = 0xffffffff & ~PORT_MASK & ~(1UL << PIN_PA2);
    in |= port_bits(port_value());
    if (pa2) {
        in |= 1UL << PIN_PA2;
    }
    GPIO.in = in;
}

static void esp_set(uint32_t v)
{
    std::lock_guard<std::mutex> l(lines);
    esp_out |= v;
    update_in();
}

static void esp_clear(uint32_t v)
{
    std::lock_guard<std::mutex> l(lines);
    if ((v & (1UL << PIN_FLAG2)) && (esp_out & (1UL << PIN_FLAG2))) {
        flag_icr = true;                // FLAG2 fell
    }
    esp_out &= ~v;
    update_in();
}

static void esp_enable_set(uint32_t v)
{
    std::lock_guard<std::mutex> l(lines);
    esp_enable |= v;
    update_in();
}

static void esp_enable_clear(uint32_t v)
{
    std::lock_guard<std::mutex> l(lines);
    esp_enable &= ~v;
    update_in();
}

void pinMode(int pin, int mode)
{
    if (mode == OUTPUT) {
        esp_enable_set(1UL << pin);
    } else {
        esp_enable_clear(1UL << pin);
    }
}

void digitalWrite(int pin, int level)
{
    if (level) {
        esp_set(1UL << pin);
    } else {
        esp_clear(1UL << pin);
    }
}

void attachInterrupt(int pin, void (*isr)(), int)
{
    if (pin == PIN_PC2) isr_pc2 = isr;
    if (pin == PIN_PA2) isr_pa2 = isr;
}

// ---------------------------------------------------------------------
// The C64's side, as src/net.asm does it
// ---------------------------------------------------------------------
static void c64_write(uint8_t b)        // sta $dd01: PC2 strobes after the write
{
    {
        std::lock_guard<std::mutex> l(lines);
        c64_pb = b;
        update_in();
    }
    isr_pc2();
}

static uint8_t c64_read()               // lda $dd01: PC2 strobes after the read
{
    uint8_t b;
    {
        std::lock_guard<std::mutex> l(lines);
        b = port_value();
    }
    isr_pc2();
    return b;
}

static void c64_pa2(bool high)
{
    bool fell;
    {
        std::lock_guard<std::mutex> l(lines);
        fell = pa2 && !high;
        pa2 = high;
        update_in();
    }
    if (fell) {
        isr_pa2();
    }
}

static void c64_ddr(bool out)
{
    std::lock_guard<std::mutex> l(lines);
    c64_drives = out;
    update_in();
}

static bool net_wait()                  // FLAG2, or a timeout of about four seconds
{
    auto start = std::chrono::steady_clock::now();
    while (!flag_icr.exchange(false)) {
        if (std::chrono::steady_clock::now() - start > std::chrono::seconds(4)) {
            return false;
        }
        std::this_thread::yield();
    }
    return true;
}

struct Response {
    bool ok = false;                    // false: the WiC64 did not answer
    uint8_t status = 0;
    std::vector<uint8_t> data;
};

// Send a request, and receive the response (unless only_send)
static Response net_request(uint8_t cmd, const std::vector<uint8_t> &payload, char protocol = 'R',
                            bool only_send = false)
{
    Response r;
    flag_icr = false;                   // lda $dd0d
    c64_pa2(true);
    c64_ddr(true);
    std::vector<uint8_t> out = {(uint8_t)protocol, cmd, (uint8_t)payload.size(), (uint8_t)(payload.size() >> 8)};
    if (protocol == 'E') {
        out.push_back(payload.size() >> 16);
        out.push_back(payload.size() >> 24);
    }
    out.insert(out.end(), payload.begin(), payload.end());
    for (uint8_t b : out) {
        c64_write(b);
        if (!net_wait()) {
            c64_ddr(false);
            return r;
        }
    }
    c64_ddr(false);                     // port B in, PA2 low: we receive
    c64_pa2(false);
    if (only_send) {
        r.ok = true;
        return r;
    }
    if (!net_wait()) {
        return r;
    }
    c64_read();                         // ready for the first byte
    auto get = [&](uint8_t &b) {
        if (!net_wait()) return false;
        b = c64_read();
        return true;
    };
    uint8_t s, lo, hi, x2 = 0, x3 = 0;
    if (!get(s) || !get(lo) || !get(hi)) {
        return r;
    }
    if (protocol == 'E' && (!get(x2) || !get(x3))) {
        return r;
    }
    uint32_t size = lo | (hi << 8) | (x2 << 16) | ((uint32_t)x3 << 24);
    r.data.resize(size);
    for (uint32_t i = 0; i < size; i++) {
        if (!get(r.data[i])) {
            return r;
        }
    }
    r.ok = true;
    r.status = s;
    return r;
}

// ---------------------------------------------------------------------
// The firmware's main loop (main.cpp), on its own thread
// ---------------------------------------------------------------------
static std::atomic<bool> running(true);

static void firmware()
{
    while (running) {
        uint8_t protocol, command;
        uint8_t *payload;
        uint32_t size;
        if (Userport::request(protocol, command, payload, size)) {
            uint32_t out_len = 0;
            uint8_t status = FileService::handle(command, payload, size,
                                                 Userport::response_payload(), Userport::response_max(), out_len,
                                                 Userport::buffer + 1024, Userport::BUFFER_SIZE - 1024);
            Userport::respond(status, out_len);
        }
        Userport::poll();
        std::this_thread::sleep_for(std::chrono::microseconds(200));
    }
}

// ---------------------------------------------------------------------
// The tests
// ---------------------------------------------------------------------
static int failures = 0, checks = 0;

#define CHECK(cond, what) do { \
    checks++; \
    if (!(cond)) { failures++; printf("FAIL  %s  (line %d)\n", what, __LINE__); } \
    else { printf("ok    %s\n", what); } \
} while (0)

static std::vector<uint8_t> bytes(const std::string &s)
{
    return std::vector<uint8_t>(s.begin(), s.end());
}

static std::string text(const std::vector<uint8_t> &v)
{
    return std::string(v.begin(), v.end());
}

static std::vector<uint8_t> file_bytes(const std::string &path)
{
    std::ifstream f(path, std::ios::binary);
    return std::vector<uint8_t>((std::istreambuf_iterator<char>(f)), std::istreambuf_iterator<char>());
}

static Response list(const std::string &path, int first = 0, int max = 255)
{
    std::vector<uint8_t> p = {(uint8_t)first, (uint8_t)(first >> 8), (uint8_t)max};
    auto pb = bytes(path);
    p.insert(p.end(), pb.begin(), pb.end());
    return net_request(0x81, p);
}

static std::vector<std::string> names(const Response &r)
{
    std::vector<std::string> out;
    if (r.data.size() < 3) return out;
    size_t i = 3;
    for (int n = 0; n < r.data[2] && i + 8 <= r.data.size(); n++) {
        size_t len = r.data[i + 7];
        std::string name(r.data.begin() + i + 8, r.data.begin() + i + 8 + len);
        out.push_back((r.data[i] ? "/" : "") + name);
        i += 8 + len;
    }
    return out;
}

static std::string joined(const std::vector<std::string> &v)
{
    std::string s;
    for (auto &x : v) s += (s.empty() ? "" : ",") + x;
    return s;
}

static Response read(const std::string &path, uint32_t off = 0, uint16_t len = 0xffff)
{
    std::vector<uint8_t> p = {(uint8_t)off, (uint8_t)(off >> 8), (uint8_t)(off >> 16), (uint8_t)(off >> 24),
                              (uint8_t)len, (uint8_t)(len >> 8)};
    auto pb = bytes(path);
    p.insert(p.end(), pb.begin(), pb.end());
    return net_request(0x82, p);
}

static Response write(const std::string &path, int mode, const std::vector<uint8_t> &data, uint32_t off = 0)
{
    std::vector<uint8_t> p = {(uint8_t)off, (uint8_t)(off >> 8), (uint8_t)(off >> 16), (uint8_t)(off >> 24),
                              (uint8_t)mode, (uint8_t)path.size()};
    auto pb = bytes(path);
    p.insert(p.end(), pb.begin(), pb.end());
    p.insert(p.end(), data.begin(), data.end());
    return net_request(0x83, p);
}

static Response one_path(uint8_t cmd, const std::string &path)
{
    return net_request(cmd, bytes(path));
}

static Response two_paths(uint8_t cmd, const std::string &from, const std::string &to)
{
    std::vector<uint8_t> p = {(uint8_t)from.size()};
    auto a = bytes(from), b = bytes(to);
    p.insert(p.end(), a.begin(), a.end());
    p.insert(p.end(), b.begin(), b.end());
    return net_request(cmd, p);
}

static int stat_kind(const Response &r) { return r.data.size() == 7 ? r.data[0] : -1; }
static uint32_t stat_size(const Response &r)
{
    return r.data.size() == 7 ? r.data[1] | (r.data[2] << 8) | (r.data[3] << 16) | ((uint32_t)r.data[4] << 24) : 0;
}
static uint16_t stat_date(const Response &r) { return r.data.size() == 7 ? r.data[5] | (r.data[6] << 8) : 0; }

static std::string last_message()
{
    return text(net_request(0x2a, {}).data);
}

static void test_protocol()
{
    printf("\n-- the transfer protocol\n");
    Response r = net_request(0x00, {});
    CHECK(r.ok && r.status == 0 && text(r.data).find("file service") != std::string::npos, "version ($00)");
    std::vector<uint8_t> blob(3000);
    for (size_t i = 0; i < blob.size(); i++) blob[i] = i * 7 + 3;
    r = net_request(0xfe, blob);
    CHECK(r.ok && r.data == blob, "echo of 3000 bytes ($FE)");
    r = net_request(0x00, {}, 'E');
    CHECK(r.ok && r.status == 0 && text(r.data).find("file service") != std::string::npos, "extended protocol ('E')");
    r = net_request(0x77, {});
    CHECK(r.ok && r.status == 2, "an undefined command: status 2");
    CHECK(last_message() == "Undefined command", "its status message ($2A)");

    // a response the C64 never collects is dropped by the next request
    net_request(0xfe, bytes("never read"), 'R', true);
    std::this_thread::sleep_for(std::chrono::milliseconds(50));
    r = net_request(0xfe, bytes("next one"));
    CHECK(r.ok && text(r.data) == "next one", "a response left unread does not upset the next request");

    // a request broken off half way is given up, and the next one works
    flag_icr = false;
    c64_pa2(true);
    c64_ddr(true);
    for (uint8_t b : {(uint8_t)'R', (uint8_t)0xfe, (uint8_t)100, (uint8_t)0, (uint8_t)1}) {
        c64_write(b);
        net_wait();
    }
    c64_ddr(false);
    std::this_thread::sleep_for(std::chrono::milliseconds(2500));
    r = net_request(0x00, {});
    CHECK(r.ok && r.status == 0, "a request broken off is given up after two seconds");
    CHECK(contention == 0, "the C64 and the ESP32 never drove port B at the same time");
}

static void test_flash(const std::string &flash)
{
    printf("\n-- volume 0, the flash\n");
    Response r = net_request(0x89, {});
    CHECK(r.ok && r.status == 0 && r.data.size() > 1, "volumes ($89)");
    if (r.data.size() > 1) {
        CHECK(r.data[0] == 1 + Settings::shares.size(), "  as many as configured");
        CHECK(r.data[1] == 0 && r.data[2] == 0 && r.data[3] == 1, "  volume 0: flash, connected");
        std::string name(r.data.begin() + 13, r.data.begin() + 13 + r.data[12]);
        CHECK(name == "System Disk", "  named System Disk");
    }
    r = net_request(0x80, {0});
    CHECK(r.ok && r.status == 0 && text(std::vector<uint8_t>(r.data.begin() + 8, r.data.end())) == "System Disk",
          "info ($80)");

    r = list("");
    CHECK(r.ok && r.status == 0, "list the top ($81)");
    CHECK(joined(names(r)) == "Brickles.app,/Empty Folder,Read Me.txt,Shapes.app,Spreadsheet.app,/System Folder",
          ("  sorted, folders marked, hidden names left out: " + joined(names(r))).c_str());
    r = list("", 2, 2);
    CHECK(r.ok && r.data[0] == 6 && joined(names(r)) == "Read Me.txt,Shapes.app", "  part of it (first 2, max 2)");
    r = list("System Folder");
    CHECK(joined(names(r)) == "Finder.sys,Interface.ovl,Shapes.ovl,System.sys", "list System Folder");

    auto sys = file_bytes(flash + "/System Folder/System.sys");
    r = read("System Folder/System.sys");
    CHECK(r.ok && r.status == 0 && r.data == sys, ("read System.sys whole (" + std::to_string(sys.size()) + " bytes)").c_str());
    r = read("System Folder/System.sys", 100, 50);
    CHECK(r.data == std::vector<uint8_t>(sys.begin() + 100, sys.begin() + 150), "read 50 bytes at 100");
    r = read("System Folder/System.sys", sys.size() + 10, 50);
    CHECK(r.status == 0 && r.data.empty(), "read past the end: nothing");
    r = read("System Folder");
    CHECK(r.status == 19, "read a folder: wrong kind (19)");
    r = read("Nothing.txt");
    CHECK(r.status == 16, "read a missing file: not found (16)");

    r = one_path(0x87, "Read Me.txt");
    CHECK(r.status == 0 && stat_kind(r) == 0 && stat_size(r) == file_bytes(flash + "/Read Me.txt").size(),
          "details of Read Me.txt ($87)");
    CHECK(stat_date(r) >> 9 >= 2024 - 1980, "  with a date");
    r = one_path(0x87, "System Folder");
    CHECK(r.status == 0 && stat_kind(r) == 1, "details of a folder");

    CHECK(write("Notes.txt", 0, bytes("Hello")).status == 0, "write a new file ($83 mode 0)");
    CHECK(write("Notes.txt", 2, bytes(" world")).status == 0, "append (mode 2)");
    CHECK(write("Notes.txt", 1, bytes("J")).status == 0, "write at 0 (mode 1)");
    CHECK(text(read("Notes.txt").data) == "Jello world", "  reads back as Jello world");
    CHECK(write("Notes.txt", 1, bytes("!"), 13).status == 0, "write past the end (mode 1)");
    CHECK(read("Notes.txt").data == bytes(std::string("Jello world\0\0!", 14)), "  extends it with zeros");
    CHECK(write("Missing.txt", 1, bytes("x")).status == 16, "mode 1 on a missing file: not found");
    CHECK(write("No Folder/x.txt", 0, bytes("x")).status == 16, "write into a missing folder: not found");
    CHECK(write("System Folder", 0, bytes("x")).status == 19, "write to a folder: wrong kind");
    std::vector<uint8_t> big(40000);
    for (size_t i = 0; i < big.size(); i++) big[i] = (i * 13) ^ (i >> 8);
    CHECK(write("Big.bin", 0, big).status == 0 && read("Big.bin").data == big, "write and read 40000 bytes");

    CHECK(one_path(0x86, "New Folder").status == 0, "new folder ($86)");
    CHECK(one_path(0x86, "New Folder").status == 17, "  again: already exists (17)");
    CHECK(two_paths(0x85, "Notes.txt", "New Folder/Notes.txt").status == 0, "move into it ($85)");
    CHECK(one_path(0x87, "Notes.txt").status == 16, "  gone from the top");
    CHECK(two_paths(0x85, "Big.bin", "New Folder/Notes.txt").status == 17, "rename onto a taken name: exists");
    CHECK(one_path(0x84, "New Folder").status == 18, "delete a full folder: not empty (18)");
    CHECK(two_paths(0x88, "New Folder/Notes.txt", "Copy.txt").status == 0, "copy ($88)");
    CHECK(text(read("Copy.txt").data) == "Jello world" + std::string("\0\0!", 3), "  the same bytes");
    CHECK(two_paths(0x88, "System Folder", "Folder Copy").status == 19, "copy a folder: wrong kind");
    CHECK(one_path(0x84, "New Folder/Notes.txt").status == 0 && one_path(0x84, "New Folder").status == 0,
          "delete a file, then its folder ($84)");
    CHECK(one_path(0x84, "Copy.txt").status == 0 && one_path(0x84, "Big.bin").status == 0, "tidy up");
    CHECK(one_path(0x84, "").status == 24, "delete the volume: denied");
    CHECK(list("../x").status == 20 && read("System Folder/../../etc").status == 20, "paths with ..: bad request (20)");
    CHECK(list("7:").status == 21, "a volume that is not there (21)");
    CHECK(last_message() == "No such volume", "  and its message");
}

static void test_share(const std::string &flash)
{
    printf("\n-- volume 1, a network share\n");
    CHECK(list("1:").status == 21, "not connected yet: 21");
    CHECK(net_request(0x8a, {1}).status == 0, "connect ($8A)");
    Response r = net_request(0x89, {});
    if (r.data.size() > 1) {
        size_t i = 1 + 12 + r.data[12];
        CHECK(r.data[i] == 1 && r.data[i + 1] == 1 && r.data[i + 2] == 1, "  volume 1: network, connected");
    }
    r = net_request(0x80, {1});
    CHECK(r.status == 0, "info on the share");
    r = list("1:");
    CHECK(r.status == 0, ("list the share: " + joined(names(r)) +
                          (r.status ? " [" + std::to_string(r.status) + ": " + last_message() + "]" : "")).c_str());

    CHECK(one_path(0x86, "1:Test Folder").status == 0, "new folder on the share");
    CHECK(one_path(0x86, "1:Test Folder").status == 17, "  again: exists");
    CHECK(write("1:Test Folder/A.txt", 0, bytes("Hello")).status == 0, "write a file on the share");
    CHECK(write("1:Test Folder/A.txt", 2, bytes(" world")).status == 0, "  append");
    CHECK(write("1:Test Folder/A.txt", 1, bytes("J")).status == 0, "  write at 0");
    CHECK(text(read("1:Test Folder/A.txt").data) == "Jello world", "  reads back");
    r = one_path(0x87, "1:Test Folder/A.txt");
    CHECK(r.status == 0 && stat_kind(r) == 0 && stat_size(r) == 11 && stat_date(r) != 0, "  details: 11 bytes, dated");
    CHECK(read("1:Nothing").status == 16, "read a missing file: not found");
    CHECK(read("1:Test Folder").status == 19, "read a folder: wrong kind");

    auto sys = file_bytes(flash + "/System Folder/System.sys");
    CHECK(two_paths(0x88, "System Folder/System.sys", "1:Test Folder/System.sys").status == 0,
          "copy System.sys from the flash to the share");
    CHECK(read("1:Test Folder/System.sys").data == sys, "  the same bytes");
    CHECK(two_paths(0x88, "1:Test Folder/A.txt", "Shared.txt").status == 0, "copy from the share to the flash");
    CHECK(text(read("Shared.txt").data) == "Jello world", "  the same bytes");
    CHECK(one_path(0x84, "Shared.txt").status == 0, "  (tidy up)");
    CHECK(two_paths(0x85, "1:Test Folder/A.txt", "A.txt").status == 20, "move between volumes: bad request");
    CHECK(two_paths(0x85, "1:Test Folder/A.txt", "1:B.txt").status == 0, "move on the share");
    CHECK(two_paths(0x85, "1:B.txt", "1:Test Folder/System.sys").status == 17, "  onto a taken name: exists");
    r = list("1:Test Folder");
    CHECK(joined(names(r)) == "System.sys", "list a folder on the share");
    r = one_path(0x84, "1:Test Folder");
    CHECK(r.status == 18, ("delete a full folder: not empty" +
                           (r.status != 18 ? " [" + std::to_string(r.status) + ": " + last_message() + "]" : "")).c_str());
    CHECK(one_path(0x84, "1:Test Folder/System.sys").status == 0 && one_path(0x84, "1:Test Folder").status == 0 &&
          one_path(0x84, "1:B.txt").status == 0, "delete files and a folder on the share");
    CHECK(one_path(0x87, "1:B.txt").status == 16, "  gone");

    CHECK(net_request(0x8b, {1}).status == 0, "disconnect ($8B)");
    CHECK(list("1:").status == 21, "  then the share is not available");
}

int main(int argc, char **argv)
{
    std::string flash, smb;
    for (int i = 1; i < argc; i++) {
        std::string a = argv[i];
        if (a == "--smb" && i + 1 < argc) {
            smb = argv[++i];
        } else {
            flash = a;
        }
    }
    if (flash.empty()) {
        fprintf(stderr, "usage: c64sim flash-folder [--smb server:port/share]\n");
        return 2;
    }
    LittleFS.root = flash;
    GPIO.out_w1ts.on_write = esp_set;
    GPIO.out_w1tc.on_write = esp_clear;
    GPIO.enable_w1ts.on_write = esp_enable_set;
    GPIO.enable_w1tc.on_write = esp_enable_clear;
    update_in();
    if (!smb.empty()) {
        size_t slash = smb.find('/');
        Settings::shares.push_back({"Public", smb.substr(0, slash).c_str(), smb.substr(slash + 1).c_str(), "", "", ""});
    }

    Userport::begin();
    FileService::begin();
    std::thread fw(firmware);

    test_protocol();
    test_flash(flash);
    if (!smb.empty()) {
        test_share(flash);
    }

    running = false;
    fw.join();
    printf("\n%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
