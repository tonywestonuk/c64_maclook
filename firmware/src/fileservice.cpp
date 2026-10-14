// fileservice.cpp - the C64's requests: a few of the WiC64's standard
// commands and the file service (docs/fileservice.md)
//
// The same service as Frodo's emulated WiC64 (frodo4/src/WiC64.cpp),
// on the ESP32's flash and network shares.

#include "fileservice.h"
#include "settings.h"
#include <WiFi.h>
#include <algorithm>

namespace FileService {

std::vector<Volume *> volumes;
static String message = "Success";

void begin()
{
    volumes.push_back(make_flash_volume(Settings::flash_name));
    for (const ShareSettings &s : Settings::shares) {
        volumes.push_back(make_smb_volume(s.name, s.server, s.share, s.user, s.password, s.domain));
    }
}

const String &status_message()
{
    return message;
}

// The response being built
static uint8_t *out_buf;
static uint32_t out_max, out_n;

static void put(uint8_t b)
{
    if (out_n < out_max) {
        out_buf[out_n] = b;
    }
    out_n++;
}

static void put32(uint32_t x)
{
    put(x);
    put(x >> 8);
    put(x >> 16);
    put(x >> 24);
}

static void put(const String &s)
{
    for (size_t i = 0; i < s.length(); i++) {
        put(s[i]);
    }
}

static uint8_t fail(uint8_t status, const String &why)
{
    message = why;
    out_n = 0;
    return status;
}

static uint8_t fail(Volume *v, uint8_t status)
{
    return fail(status, v->error);
}

static uint32_t get32(const uint8_t *p)
{
    return p[0] | (p[1] << 8) | (p[2] << 16) | ((uint32_t)p[3] << 24);
}

static String string_of(const uint8_t *p, uint32_t n)
{
    String s;
    s.reserve(n);
    for (uint32_t i = 0; i < n && p[i]; i++) {
        s += (char)p[i];
    }
    return s;
}

// A name as the C64 sees it: printable ASCII only
static String c64_name(const String &name)
{
    String out;
    for (size_t i = 0; i < name.length(); i++) {
        unsigned char c = name[i];
        out += (c >= 32 && c < 127 && c != '/' && c != ':') ? (char)c : '?';
    }
    return out.substring(0, 255);
}

// Is volume n there and connected?
static Volume *volume(int n, uint8_t &status)
{
    if (n < 0 || n >= (int)volumes.size()) {
        status = fail(ST_NO_SHARE, "No such volume");
        return nullptr;
    }
    if (!volumes[n]->connected()) {
        status = fail(ST_NO_SHARE, volumes[n]->network ? "The share is not connected"
                                                       : "The flash is not available");
        return nullptr;
    }
    return volumes[n];
}

// "n:path" (or "path", on volume 0) -> the volume and the path on it
static Volume *resolve(const String &full, String &path, uint8_t &status)
{
    int vol = 0;
    String rel = full;
    if (rel.length() >= 2 && rel[0] >= '0' && rel[0] <= '9' && rel[1] == ':') {
        vol = rel[0] - '0';
        rel = rel.substring(2);
    }
    Volume *v = volume(vol, status);
    if (!v) {
        return nullptr;
    }
    path = "";
    int start = 0;
    while (start <= (int)rel.length()) {
        int end = rel.indexOf('/', start);
        if (end < 0) {
            end = rel.length();
        }
        String part = rel.substring(start, end);
        if (part == "." || part == ".." || part.indexOf(':') >= 0 || part.indexOf('\\') >= 0) {
            status = fail(ST_BAD_REQUEST, "Bad path");
            return nullptr;
        }
        if (part.length()) {
            if (path.length()) {
                path += '/';
            }
            path += part;
        }
        start = end + 1;
    }
    return v;
}

static void put_space(Volume *v)
{
    uint64_t total = 0, avail = 0;
    if (v->connected()) {
        v->space(total, avail);
    }
    put32(std::min<uint64_t>(total, 0xffffffff));
    put32(std::min<uint64_t>(avail, 0xffffffff));
}

static uint8_t cmd_info(const uint8_t *p, uint32_t n)
{
    uint8_t st;
    Volume *v = volume(n ? p[0] : 0, st);
    if (!v) {
        return st;
    }
    put_space(v);
    put(c64_name(v->name));
    return ST_OK;
}

static uint8_t cmd_volumes()
{
    put(volumes.size());
    for (size_t i = 0; i < volumes.size(); i++) {
        Volume *v = volumes[i];
        String name = c64_name(v->name);
        put(i);
        put(v->network ? 1 : 0);
        put(v->connected() ? 1 : 0);
        put_space(v);
        put(name.length());
        put(name);
    }
    return ST_OK;
}

static uint8_t cmd_connect(const uint8_t *p, uint32_t n, bool connect)
{
    int i = n ? p[0] : -1;
    if (i < 0 || i >= (int)volumes.size()) {
        return fail(ST_NO_SHARE, "No such volume");
    }
    Volume *v = volumes[i];
    if (!v->network) {              // the flash is always there
        return ST_OK;
    }
    if (!connect) {
        v->disconnect();
        return ST_OK;
    }
    if (WiFi.status() != WL_CONNECTED) {
        return fail(ST_NO_SHARE, "The WiC64 is not on a network");
    }
    int st = v->connect();
    return st ? fail(v, st) : ST_OK;
}

static uint8_t cmd_list(const uint8_t *p, uint32_t n)
{
    if (n < 3) {
        return fail(ST_BAD_REQUEST, "Bad request");
    }
    unsigned first = p[0] | (p[1] << 8);
    unsigned max = p[2];
    String path;
    uint8_t st;
    Volume *v = resolve(string_of(p + 3, n - 3), path, st);
    if (!v) {
        return st;
    }
    std::vector<Entry> all;
    if (int r = v->list(path, all)) {
        return fail(v, r);
    }
    std::vector<Entry> entries;
    for (Entry &e : all) {
        if (e.name.length() && e.name[0] != '.') {
            e.name = c64_name(e.name);
            entries.push_back(e);
        }
    }
    std::sort(entries.begin(), entries.end(), [](const Entry &a, const Entry &b) {
        return strcasecmp(a.name.c_str(), b.name.c_str()) < 0;
    });

    put(entries.size() & 0xff);
    put(entries.size() >> 8);
    put(0);                         // the count, filled in below
    unsigned count = 0;
    for (size_t i = first; i < entries.size() && count < max; i++) {
        const Entry &e = entries[i];
        if (out_n + 9 + e.name.length() > 0xffff) {
            break;
        }
        put(e.dir ? 1 : 0);
        put32(e.size);
        put(e.date & 0xff);
        put(e.date >> 8);
        put(e.name.length());
        put(e.name);
        count++;
    }
    out_buf[2] = count;
    return ST_OK;
}

static uint8_t cmd_read(const uint8_t *p, uint32_t n)
{
    if (n < 6) {
        return fail(ST_BAD_REQUEST, "Bad request");
    }
    uint32_t offset = get32(p);
    uint32_t length = std::min<uint32_t>(p[4] | (p[5] << 8), out_max);
    String path;
    uint8_t st;
    Volume *v = resolve(string_of(p + 6, n - 6), path, st);
    if (!v) {
        return st;
    }
    uint32_t got;
    if (int r = v->read(path, offset, out_buf, length, got)) {
        return fail(v, r);
    }
    out_n = got;
    return ST_OK;
}

static uint8_t cmd_write(const uint8_t *p, uint32_t n)
{
    if (n < 6 || n < 6u + p[5]) {
        return fail(ST_BAD_REQUEST, "Bad request");
    }
    uint32_t offset = get32(p);
    uint8_t mode = p[4];
    uint8_t plen = p[5];
    String path;
    uint8_t st;
    Volume *v = resolve(string_of(p + 6, plen), path, st);
    if (!v) {
        return st;
    }
    if (path.length() == 0) {
        return fail(ST_WRONG_KIND, "That is a folder");
    }
    if (int r = v->write(path, mode, offset, p + 6 + plen, n - 6 - plen)) {
        return fail(v, r);
    }
    return ST_OK;
}

static uint8_t cmd_delete(const uint8_t *p, uint32_t n)
{
    String path;
    uint8_t st;
    Volume *v = resolve(string_of(p, n), path, st);
    if (!v) {
        return st;
    }
    if (path.length() == 0) {
        return fail(ST_DENIED, "A volume cannot be deleted");
    }
    if (int r = v->remove(path)) {
        return fail(v, r);
    }
    return ST_OK;
}

// Copy a file, also from one volume to another, through scratch
static uint8_t copy_file(Volume *va, const String &a, Volume *vb, const String &b,
                         uint8_t *scratch, uint32_t scratch_size)
{
    uint32_t off = 0;
    while (true) {
        uint32_t got;
        if (int r = va->read(a, off, scratch, scratch_size, got)) {
            if (off) {
                vb->remove(b);
            }
            return fail(va, r);
        }
        if (off == 0 || got) {
            if (int r = vb->write(b, off ? 2 : 0, 0, scratch, got)) {
                vb->remove(b);
                return fail(vb, r);
            }
        }
        off += got;
        if (got < scratch_size) {
            return ST_OK;
        }
    }
}

static uint8_t cmd_rename(const uint8_t *p, uint32_t n, bool copy, uint8_t *scratch, uint32_t scratch_size)
{
    if (n < 1 || n < 1u + p[0]) {
        return fail(ST_BAD_REQUEST, "Bad request");
    }
    String from, to;
    uint8_t st;
    Volume *va = resolve(string_of(p + 1, p[0]), from, st);
    if (!va) {
        return st;
    }
    Volume *vb = resolve(string_of(p + 1 + p[0], n - 1 - p[0]), to, st);
    if (!vb) {
        return st;
    }
    if (from.length() == 0 || to.length() == 0) {
        return fail(ST_DENIED, "A volume cannot be moved");
    }
    if (!copy) {
        if (va != vb) {
            return fail(ST_BAD_REQUEST, "Things can only be moved within a volume");
        }
        int r = va->rename(from, to);
        return r ? fail(va, r) : ST_OK;
    }
    Entry e;
    if (int r = va->stat(from, e)) {
        return fail(va, r);
    }
    if (e.dir) {
        return fail(ST_WRONG_KIND, "Folders cannot be copied");
    }
    if (vb->stat(to, e) == ST_OK) {
        return fail(ST_EXISTS, "The name is already taken");
    }
    return copy_file(va, from, vb, to, scratch, scratch_size);
}

static uint8_t cmd_mkdir(const uint8_t *p, uint32_t n)
{
    String path;
    uint8_t st;
    Volume *v = resolve(string_of(p, n), path, st);
    if (!v) {
        return st;
    }
    if (int r = v->mkdir(path)) {
        return fail(v, r);
    }
    return ST_OK;
}

static uint8_t cmd_stat(const uint8_t *p, uint32_t n)
{
    String path;
    uint8_t st;
    Volume *v = resolve(string_of(p, n), path, st);
    if (!v) {
        return st;
    }
    Entry e;
    if (int r = v->stat(path, e)) {
        return fail(v, r);
    }
    put(e.dir ? 1 : 0);
    put32(e.size);
    put(e.date & 0xff);
    put(e.date >> 8);
    return ST_OK;
}

uint8_t handle(uint8_t cmd, const uint8_t *p, uint32_t n,
               uint8_t *out, uint32_t max, uint32_t &out_len,
               uint8_t *scratch, uint32_t scratch_size)
{
    out_buf = out;
    out_max = max;
    out_n = 0;
    String last = message;
    message = "Success";
    uint8_t st = ST_OK;

    switch (cmd) {

        // A few of the WiC64's standard commands
        case 0x00:      // version string
            put("WiC64 desktop64 file service 1.0");
            break;
        case 0x26:      // version numbers: major, minor, patch, development
            put(2); put(0); put(0); put(0);
            break;
        case 0x06:      // IP address
            put(WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString() : String("0.0.0.0"));
            break;
        case 0x10:      // SSID
            put(Settings::wifi_ssid);
            break;
        case 0x2c:      // connected?
            if (WiFi.status() != WL_CONNECTED) {
                st = fail(ST_INTERNAL, "Not connected");
            }
            break;
        case 0x2f:      // configured?
            if (Settings::wifi_ssid.length() == 0) {
                st = fail(ST_INTERNAL, "Not configured");
            }
            break;
        case 0x2d:      // set transfer timeout
        case 0x32:      // set remote timeout
            break;
        case 0x2a:      // the status message of the last request
            put(last);
            message = last;
            break;
        case 0xfe:      // echo
            memmove(out, p, std::min(n, max));
            out_n = std::min(n, max);
            break;

        // The file service
        case 0x80: st = cmd_info(p, n); break;
        case 0x81: st = cmd_list(p, n); break;
        case 0x82: st = cmd_read(p, n); break;
        case 0x83: st = cmd_write(p, n); break;
        case 0x84: st = cmd_delete(p, n); break;
        case 0x85: st = cmd_rename(p, n, false, scratch, scratch_size); break;
        case 0x86: st = cmd_mkdir(p, n); break;
        case 0x87: st = cmd_stat(p, n); break;
        case 0x88: st = cmd_rename(p, n, true, scratch, scratch_size); break;
        case 0x89: st = cmd_volumes(); break;
        case 0x8a: st = cmd_connect(p, n, true); break;
        case 0x8b: st = cmd_connect(p, n, false); break;

        default:
            st = fail(ST_CLIENT, "Undefined command");
            break;
    }
    out_len = std::min(out_n, out_max);
    return st;
}

}  // namespace FileService
