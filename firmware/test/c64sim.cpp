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
#include "driver/gpio.h"
#include "../src/userport.h"
#include "../src/fileservice.h"
#include "../src/settings.h"

#include <atomic>
#include <cmath>
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

// PC2's falling edges are latched in GPIO.status; with its interrupt on,
// the interrupt takes them (and clears the latch)
static std::atomic<bool> pc2_irq(true);

void gpio_intr_disable(gpio_num_t pin)
{
    if (pin == PIN_PC2) pc2_irq = false;
}

void gpio_intr_enable(gpio_num_t pin)
{
    if (pin == PIN_PC2) pc2_irq = true;
}

static void status_clear(uint32_t v)
{
    std::lock_guard<std::mutex> l(lines);
    GPIO.status = GPIO.status & ~v;
}

static void strobe()                    // PC2 pulses low
{
    {
        std::lock_guard<std::mutex> l(lines);
        GPIO.status = GPIO.status | (1UL << PIN_PC2);
    }
    if (pc2_irq) {
        status_clear(1UL << PIN_PC2);
        isr_pc2();
    }
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
    strobe();
}

static uint8_t c64_read()               // lda $dd01: PC2 strobes after the read
{
    uint8_t b;
    {
        std::lock_guard<std::mutex> l(lines);
        b = port_value();
    }
    strobe();
    return b;
}

// lda $dd01 in a burst: no wait for FLAG2.  (The WiC64 is quicker than
// the C64: the next read comes once it has seen this one.)
static uint8_t c64_read_burst()
{
    uint8_t b;
    {
        std::lock_guard<std::mutex> l(lines);
        b = port_value();
    }
    strobe();
    auto start = std::chrono::steady_clock::now();
    while (GPIO.status & (1UL << PIN_PC2)) {
        if (std::chrono::steady_clock::now() - start > std::chrono::seconds(4)) {
            break;
        }
        std::this_thread::yield();
    }
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

// Send a request, and receive the response (unless only_send; in a burst
// if burst)
static Response net_request(uint8_t cmd, const std::vector<uint8_t> &payload, char protocol = 'R',
                            bool only_send = false, bool burst = false)
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
    if (burst) {                        // npu_draw: read after read
        c64_read_burst();
        uint8_t s = c64_read_burst(), lo = c64_read_burst(), hi = c64_read_burst();
        r.data.resize(lo | (hi << 8));
        for (uint8_t &b : r.data) {
            b = c64_read_burst();
        }
        r.ok = true;
        r.status = s;
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
    CHECK(joined(names(r)) == "Brickles.app,/Empty Folder,Polyhedron.app,Read Me.txt,Shapes.app,Spreadsheet.app,/System Folder",
          ("  sorted, folders marked, hidden names left out: " + joined(names(r))).c_str());
    r = list("", 2, 2);
    CHECK(r.ok && r.data[0] == 7 && joined(names(r)) == "Polyhedron.app,Read Me.txt", "  part of it (first 2, max 2)");
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

// ---------------------------------------------------------------------
// The matrix unit (docs/npu.md), command $90
// ---------------------------------------------------------------------
struct Prog {
    std::vector<uint8_t> b;
    Prog &op(std::initializer_list<int> v) { for (int x : v) b.push_back(x); return *this; }
    Prog &k(double x)                       // a 16.16 constant
    {
        int32_t v = (int32_t)llround(x * 65536.0);
        for (int i = 0; i < 4; i++) b.push_back((v >> (8 * i)) & 0xff);
        return *this;
    }
    Prog &s16(std::initializer_list<int> v) { for (int x : v) { b.push_back(x & 0xff); b.push_back((x >> 8) & 0xff); } return *this; }
};

// The elements of the STOREd matrix at offset at (16-bit)
static std::vector<int> s16s(const Response &r, size_t at = 0)
{
    std::vector<int> v;
    if (r.data.size() < at + 2) return v;
    size_t count = r.data[at] * r.data[at + 1];
    for (size_t i = 0; i < count && at + 3 + 2 * i < r.data.size(); i++) {
        v.push_back((int16_t)(r.data[at + 2 + 2 * i] | (r.data[at + 3 + 2 * i] << 8)));
    }
    return v;
}

static std::string ints(const std::vector<int> &v)
{
    std::string s;
    for (int x : v) s += (s.empty() ? "" : " ") + std::to_string(x);
    return s;
}

static Response npu(const Prog &p) { return net_request(0x90, p.b); }

static void test_npu()
{
    printf("\n-- the matrix unit ($90)\n");
    Response r = npu(Prog().op({0x0a, 0x01, 0, 2, 3, 0x00}).s16({1, 2, 3, 4, 5, 6}).op({0x02, 0, 0x00}));
    CHECK(r.status == 0 && r.data.size() == 14 && r.data[0] == 2 && r.data[1] == 3 && ints(s16s(r)) == "1 2 3 4 5 6",
          "LOAD and STORE a 2x3 matrix");
    r = npu(Prog().op({0x07, 1, 0, 0x02, 1, 0x00}));
    CHECK(r.data.size() > 1 && r.data[0] == 3 && r.data[1] == 2 && ints(s16s(r)) == "1 4 2 5 3 6",
          "TRANSP, on a register kept from the last request");
    r = npu(Prog().op({0x14, 2, 0, 1, 0x02, 2, 0x00}));
    CHECK(ints(s16s(r)) == "14 32 32 77", "MUL: 2x3 by 3x2");
    r = npu(Prog().op({0x14, 2, 0, 0}));
    CHECK(r.status == 33, "MUL of 2x3 by 2x3: the sizes don't fit (33)");
    CHECK(last_message() == "Instruction 1 (MUL): can't multiply 2x3 by 2x3", ("  " + last_message()).c_str());

    r = npu(Prog().op({0x20, 1, 3}).s16({0x4000}).op({0x01, 0, 2, 1, 0x00}).s16({100, 0})
                  .op({0x14, 2, 1, 0, 0x02, 2, 0x00}));
    CHECK(ints(s16s(r)) == "0 100", "ROTATE a quarter turn: (100, 0) to (0, 100)");

    // a hexagon of radius 100 at (160, 100), worked out and turned on the WiC64
    Prog setup;
    setup.op({0x05, 4, 1, 6}).k(0).k(2 * M_PI)          // RANGE
         .op({0x03, 5, 1, 1}).k(6)                      // FILL
         .op({0x13, 4, 4, 5})                           // EDIV
         .op({0x17, 5, 4, 9, 0x17, 6, 4, 8})            // APPLY cos, sin
         .op({0x08, 0, 5, 6, 1})                        // JOIN
         .op({0x15, 0, 0}).k(100)                       // SCALE
         .op({0x01, 3, 2, 1, 0x00}).s16({160, 100});    // LOAD the centre
    r = npu(setup);
    CHECK(r.status == 0 && r.data.empty(), "a program that works out a hexagon's corners");
    Prog frame;
    frame.op({0x20, 1, 3}).s16({0}).op({0x14, 2, 1, 0, 0x10, 2, 2, 3, 0x02, 2, 0x00});
    CHECK(frame.b.size() == 16, "  a frame program of 16 bytes");
    r = npu(frame);
    CHECK(r.data.size() == 26 && ints(s16s(r)) == "260 210 110 60 110 210 100 187 187 100 13 13",
          ("  the hexagon's corners: " + ints(s16s(r))).c_str());
    frame.b[3] = 0x00;
    frame.b[4] = 0x20;                                  // an eighth of a turn
    r = npu(frame);
    CHECK(ints(s16s(r)).rfind("231 ", 0) == 0, ("  turned by 45 degrees: " + ints(s16s(r))).c_str());

    // 3D: a point turned about y, then seen in perspective
    r = npu(Prog().op({0x01, 7, 3, 2, 0x00}).s16({100, 100, 0, 0, 0, 256})
                  .op({0x21, 8, 7}).k(256).op({0x02, 8, 0x00}));
    CHECK(ints(s16s(r)) == "100 50 0 0", "PROJECT: twice as far away, half as far out");

    // formats and functions
    r = npu(Prog().op({0x01, 9, 1, 4, 0x08}).s16({128, -64, 256 * 100, 3})
                  .op({0x02, 9, 0x16, 0x02, 9, 0x20, 0x17, 10, 9, 3, 0x02, 10, 0x08}));
    std::vector<uint8_t> want = {1, 4, 32, 0xf0, 127, 1, 1, 4, 1, 0, 100, 0};
    CHECK(r.data.size() >= 12 && std::vector<uint8_t>(r.data.begin(), r.data.begin() + 12) == want,
          "8.8 in, signed 2.6 and unsigned bytes out, held to their range");
    CHECK(ints(s16s(r, 12)) == "159 112 256 129", "APPLY sigmoid (8.8 out)");
    r = npu(Prog().op({0x01, 11, 2, 2, 0x00}).s16({1, 5, 1, 2}).op({0x18, 12, 11, 0x02, 12, 0x08, 0x1a, 13, 11,
                       0x02, 13, 0x00, 0x19, 14, 11, 1, 0x02, 14, 0x00}));
    CHECK(ints(s16s(r)) == "128 244 128 12", "SOFTMAX of each column");
    CHECK(ints(s16s(r, 10)) == "0 0", "ARGMAX of each column");
    CHECK(ints(s16s(r, 16)) == "6 3", "SUM of each row");
    r = npu(Prog().op({0x01, 11, 1, 1, 0x00}).s16({7}).op({0x01, 12, 2, 2, 0x00}).s16({14, 32, 32, 77})
                  .op({0x10, 13, 12, 11, 0x02, 13, 0x00}));
    CHECK(ints(s16s(r)) == "21 39 39 84", "ADD one element to every element (a broadcast)");
    r = npu(Prog().op({0x01, 11, 2, 1, 0x00}).s16({100, -100}).op({0x10, 13, 12, 11, 0x02, 13, 0x00}));
    CHECK(ints(s16s(r)) == "114 132 -68 -23", "ADD a column to every column");

    r = npu(Prog().op({0x09, 0, 0x02, 0, 0x00}));
    CHECK(r.status == 32, "a register used after FREE: empty (32)");
    r = npu(Prog().op({0x55}));
    CHECK(r.status == 20, "an unknown instruction: bad program (20)");
    r = npu(Prog().op({0x01, 0, 2, 2, 0x00, 1, 0}));
    CHECK(r.status == 20, "LOAD with its data cut short: bad program");
    r = npu(Prog().op({0x03, 15, 255, 255}).k(1));
    CHECK(r.status == 34, "a 255x255 matrix: out of matrix memory (34)");
    r = npu(Prog().op({0x0a}));
    CHECK(r.status == 0, "RESET");

    // scripts kept on the WiC64
    r = npu(Prog().op({0x01, 20, 1, 1, 0x00}).s16({0}).op({0x01, 21, 1, 1, 0x00}).s16({1})
                  .op({0x0b, 1, 7, 0, 0x10, 20, 20, 21, 0x02, 20, 0x00}));
    CHECK(r.status == 0 && r.data.empty(), "DEFINE a script (it isn't run)");
    std::string counts;
    for (int i = 0; i < 3; i++) {
        r = npu(Prog().op({0x0c, 1}));
        counts += (counts.empty() ? "" : " ") + ints(s16s(r));
    }
    CHECK(counts == "1 2 3", ("RUN it three times, a request each: " + counts).c_str());
    r = npu(Prog().op({0x0c, 5}));
    CHECK(r.status == 32 && last_message() == "Instruction 1 (RUN): script 5 is empty",
          "RUN an empty script: empty (32)");
    r = npu(Prog().op({0x01, 23, 2, 2, 0x00}).s16({1, 2, 3, 4}).op({0x0b, 2, 4, 0, 0x14, 22, 23, 20, 0x0c, 2}));
    CHECK(r.status == 33 && last_message() == "Script 2, instruction 1 (MUL): can't multiply 2x2 by 1x1",
          ("an error in a script says where: " + last_message()).c_str());
    r = npu(Prog().op({0x0b, 3, 2, 0, 0x0c, 3, 0x0c, 3}));
    CHECK(r.status == 20 && last_message().find("too deeply") != std::string::npos,
          "a script that runs itself: stopped (20)");

    // the clock, and turning by an angle kept in a register
    r = npu(Prog().op({0x0d, 24, 0x02, 24, 0x08}));
    CHECK(ints(s16s(r)) == "0", "CLOCK the first time: 0");
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    r = npu(Prog().op({0x0d, 24, 0x02, 24, 0x08}));
    int t = s16s(r).empty() ? -1 : s16s(r)[0];
    CHECK(t >= 20 && t <= 40, ("CLOCK after 0.1 s: " + std::to_string(t / 256.0) + " s").c_str());
    r = npu(Prog().op({0x01, 25, 1, 2, 0x08}).s16({0, 402}).op({0x22, 26, 3, 25, 1})
                  .op({0x01, 27, 2, 1, 0x00}).s16({100, 0}).op({0x14, 28, 26, 27, 0x02, 28, 0x00}));
    CHECK(ints(s16s(r)) == "0 100", "TURN by element 1 of a register (pi/2): (100, 0) to (0, 100)");
    r = npu(Prog().op({0x22, 26, 3, 25, 2}));
    CHECK(r.status == 33, "TURN by an element that isn't there: sizes (33)");
}

// ---------------------------------------------------------------------
// Drawing on the WiC64 (SCREEN, CLEAR, LINES, SEND), its changes sent in
// a burst ($91) and written into a C64 bitmap as npu_draw does
// ---------------------------------------------------------------------
static std::vector<uint8_t> bitmap(8000, 0x55);

static int screen_byte(int x, int y) { return (y >> 3) * 320 + (x >> 3) * 8 + (y & 7); }
static bool pixel(int x, int y) { return bitmap[screen_byte(x, y)] & (0x80 >> (x & 7)); }

// the runs into the bitmap: their number, or -1 if one is out of bounds
static int apply_runs(const std::vector<uint8_t> &d)
{
    int runs = 0;
    size_t i = 0;
    while (i < d.size()) {
        if (i + 3 > d.size()) return -1;
        int at = d[i] | ((d[i + 1] & 0x1f) << 8), step = (d[i + 1] & 0x80) ? 8 : 1, n = d[i + 2];
        if (n == 0 || at + (n - 1) * step >= 8000 || (step == 8 && n > 32) || i + 3 + n > d.size()) return -1;
        for (int k = 0; k < n; k++) bitmap[at + k * step] = d[i + 3 + k];
        i += 3 + n;
        runs++;
    }
    return runs;
}

static int black_in(int x1, int y1, int x2, int y2)
{
    int n = 0;
    for (int y = y1; y <= y2; y++)
        for (int x = x1; x <= x2; x++) n += pixel(x, y);
    return n;
}

static Response draw(const Prog &p) { return net_request(0x91, p.b, 'R', false, true); }

static void test_screen()
{
    printf("\n-- drawing on the WiC64, sent in a burst ($91)\n");
    // the window's content: 256 x 164 at (32, 40), white; the rest of the screen 0x55
    for (int y = 40; y < 204 && y < 200; y++)
        for (int x = 32; x < 288; x += 8) bitmap[screen_byte(x, y)] = 0;
    Prog p;
    p.op({0x30}).s16({32, 40, 256, 164})                        // SCREEN
     .op({0x01, 26, 2, 3, 0x00}).s16({10, 100, 100, 10, 10, 60})   // points (10,10) (100,10) (100,60)
     .op({0x01, 27, 2, 2, 0x20, 0, 1, 1, 2})                    // edges 0-1, 1-2
     .op({0x31, 0x32, 26, 27, 255, 0x33});                      // CLEAR, LINES, SEND
    Response r = draw(p);
    int runs = apply_runs(r.data);
    CHECK(r.ok && r.status == 0 && runs > 0, ("SCREEN, LINES, SEND: " + std::to_string(r.data.size()) +
                                             " bytes in " + std::to_string(runs) + " runs").c_str());
    CHECK(black_in(32, 40, 287, 199) == 141 && pixel(42, 50) && pixel(132, 50) && pixel(132, 100),
          "  a 91-pixel line across and a 51-pixel line down, where they belong");
    bool outside = true;
    for (int y = 0; y < 200; y++)
        for (int x = 0; x < 320; x += 8)
            if ((x < 32 || x >= 288 || y < 40) && bitmap[screen_byte(x, y)] != 0x55) outside = false;
    CHECK(outside, "  nothing outside the window written");

    r = draw(Prog().op({0x33}));
    CHECK(r.status == 0 && r.data.empty(), "SEND again with nothing changed: nothing");

    p = Prog();
    p.op({0x01, 26, 2, 3, 0x00}).s16({20, 110, 110, 20, 20, 70}) // moved by (10, 10)
     .op({0x31, 0x32, 26, 27, 255, 0x33});
    r = draw(p);
    runs = apply_runs(r.data);
    CHECK(runs > 0 && black_in(32, 40, 287, 199) == 141 && !pixel(42, 50) && pixel(52, 60) && pixel(142, 110),
          ("the next frame, moved: the old lines gone, the new ones there (" +
           std::to_string(r.data.size()) + " bytes)").c_str());

    p = Prog();
    p.op({0x01, 28, 1, 2, 0x00}).s16({1, 0}).op({0x31, 0x32, 26, 27, 28, 0x33});
    r = draw(p);
    apply_runs(r.data);
    CHECK(black_in(32, 40, 287, 199) == 91, "LINES with a mask: only the first line");

    r = draw(Prog().op({0x31, 0x33}));
    apply_runs(r.data);
    CHECK(black_in(32, 40, 287, 199) == 0, "CLEAR and SEND: the window white again");

    r = draw(Prog().op({0x30}).s16({35, 40, 100, 20}).op({0x01, 26, 2, 2, 0x00}).s16({-10, 200, 5, 5})
                   .op({0x01, 27, 2, 1, 0x20, 0, 1, 0x31, 0x32, 26, 27, 255, 0x33}));
    apply_runs(r.data);
    CHECK(black_in(32, 45, 287, 45) == 88 && pixel(40, 45) && pixel(127, 45) && !pixel(39, 45) && !pixel(128, 45),
          "a window at x = 35: drawn in the whole bytes inside it (40..127), clipped");

    r = draw(Prog().op({0x01, 29, 1, 3, 0x00}).s16({7, 8, 9}).op({0x02, 29, 0x00}));
    CHECK(r.status == 0 && ints(s16s(r)) == "7 8 9", "any results can come in a burst (STORE)");
    r = draw(Prog().op({0x55}));
    CHECK(r.status == 20 && r.data.empty(), "an error in a burst: just the status");

    // PICK and STEP, for working out which edges to draw
    r = npu(Prog().op({0x01, 29, 1, 3, 0x00}).s16({10, 20, 30}).op({0x01, 30, 2, 3, 0x20, 9, 9, 9, 2, 0, 1})
                  .op({0x1b, 31, 29, 30, 1, 0x02, 31, 0x00}));
    CHECK(ints(s16s(r)) == "30 10 20", "PICK: elements of a, by the numbers in a row of b");
    r = npu(Prog().op({0x01, 29, 1, 3, 0x00}).s16({-1, 0, 2}).op({0x17, 29, 29, 13, 0x02, 29, 0x00}));
    CHECK(ints(s16s(r)) == "0 0 1", "APPLY step: 1 above 0, else 0");
    CHECK(contention == 0, "the C64 and the ESP32 never drove port B at the same time");
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
    GPIO.status_w1tc.on_write = status_clear;
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
    test_npu();
    test_screen();
    if (!smb.empty()) {
        test_share(flash);
    }

    running = false;
    fw.join();
    printf("\n%d checks, %d failed\n", checks, failures);
    return failures ? 1 : 0;
}
