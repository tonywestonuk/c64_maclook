// shim.cpp - the host side of the test bench's Arduino stand-ins:
// time, Wi-Fi, and LittleFS on a host folder

#include "Arduino.h"
#include "LittleFS.h"
#include "WiFi.h"
#include <chrono>
#include <dirent.h>
#include <sys/stat.h>
#include <thread>
#include <unistd.h>

static const auto t0 = std::chrono::steady_clock::now();

int64_t esp_timer_get_time()
{
    return std::chrono::duration_cast<std::chrono::microseconds>(std::chrono::steady_clock::now() - t0).count();
}

uint32_t millis()
{
    return (uint32_t)(esp_timer_get_time() / 1000);
}

void delay(uint32_t ms)
{
    std::this_thread::sleep_for(std::chrono::milliseconds(ms));
}

WiFiClass WiFi;
LittleFSClass LittleFS;

struct FileImpl {
    std::string host;
    std::string name;
    bool dir = false;
    FILE *fp = nullptr;
    DIR *dp = nullptr;
    ~FileImpl()
    {
        if (fp) fclose(fp);
        if (dp) closedir(dp);
    }
};

static std::string base_name(const std::string &p)
{
    size_t slash = p.rfind('/');
    return slash == std::string::npos ? p : p.substr(slash + 1);
}

static File open_host(const std::string &host, const char *mode)
{
    struct stat st;
    bool exists = ::stat(host.c_str(), &st) == 0;
    auto impl = std::make_shared<FileImpl>();
    impl->host = host;
    impl->name = base_name(host);
    if (exists && S_ISDIR(st.st_mode)) {
        if (mode[0] != 'r' || mode[1]) {
            return File();
        }
        impl->dir = true;
        impl->dp = opendir(host.c_str());
        return impl->dp ? File(impl) : File();
    }
    std::string m = mode;
    if (m == "r") {
        m = "rb";
    } else if (m == "w") {
        m = "wb";
    } else if (m == "a") {
        m = "ab";
    } else if (m == "r+") {
        m = "r+b";
    }
    impl->fp = fopen(host.c_str(), m.c_str());
    return impl->fp ? File(impl) : File();
}

File::operator bool() const { return impl_ && (impl_->fp || impl_->dp); }
bool File::isDirectory() const { return impl_ && impl_->dir; }

size_t File::size() const
{
    struct stat st;
    if (!impl_) return 0;
    if (impl_->fp) fflush(impl_->fp);
    return ::stat(impl_->host.c_str(), &st) == 0 ? st.st_size : 0;
}

bool File::seek(uint32_t pos) { return impl_ && impl_->fp && fseek(impl_->fp, pos, SEEK_SET) == 0; }

size_t File::read(uint8_t *buf, size_t len)
{
    return impl_ && impl_->fp ? fread(buf, 1, len, impl_->fp) : 0;
}

size_t File::write(const uint8_t *buf, size_t len)
{
    return impl_ && impl_->fp ? fwrite(buf, 1, len, impl_->fp) : 0;
}

void File::close() { impl_.reset(); }
const char *File::name() const { return impl_ ? impl_->name.c_str() : ""; }

File File::openNextFile()
{
    if (!impl_ || !impl_->dp) return File();
    while (struct dirent *de = readdir(impl_->dp)) {
        if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..")) continue;
        return open_host(impl_->host + "/" + de->d_name, "r");
    }
    return File();
}

time_t File::getLastWrite() const
{
    struct stat st;
    return impl_ && ::stat(impl_->host.c_str(), &st) == 0 ? st.st_mtime : 0;
}

bool LittleFSClass::begin(bool) { return true; }
File LittleFSClass::open(const String &path, const char *mode) { return open_host(root + path.c_str(), mode); }

bool LittleFSClass::exists(const String &path)
{
    struct stat st;
    return ::stat((root + path.c_str()).c_str(), &st) == 0;
}

bool LittleFSClass::mkdir(const String &path) { return ::mkdir((root + path.c_str()).c_str(), 0755) == 0; }
bool LittleFSClass::rmdir(const String &path) { return ::rmdir((root + path.c_str()).c_str()) == 0; }
bool LittleFSClass::remove(const String &path) { return ::unlink((root + path.c_str()).c_str()) == 0; }

bool LittleFSClass::rename(const String &from, const String &to)
{
    return ::rename((root + from.c_str()).c_str(), (root + to.c_str()).c_str()) == 0;
}

size_t LittleFSClass::totalBytes() { return 0x270000; }    // the partition (partitions.csv)

static size_t used_in(const std::string &dir)
{
    size_t used = 4096;
    DIR *dp = opendir(dir.c_str());
    if (!dp) return used;
    while (struct dirent *de = readdir(dp)) {
        if (!strcmp(de->d_name, ".") || !strcmp(de->d_name, "..")) continue;
        std::string p = dir + "/" + de->d_name;
        struct stat st;
        if (::stat(p.c_str(), &st) == 0) {
            used += S_ISDIR(st.st_mode) ? used_in(p) : (st.st_size + 4095) / 4096 * 4096;
        }
    }
    closedir(dp);
    return used;
}

size_t LittleFSClass::usedBytes() { return used_in(root); }
