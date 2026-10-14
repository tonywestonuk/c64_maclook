// LittleFS.h - the ESP32's LittleFS, as a folder on the host (for the
// test bench).  Only what the firmware uses.

#pragma once
#include "Arduino.h"
#include <memory>

struct FileImpl;

class File {
public:
    File() {}
    explicit File(std::shared_ptr<FileImpl> impl) : impl_(impl) {}
    explicit operator bool() const;
    bool isDirectory() const;
    size_t size() const;
    bool seek(uint32_t pos);
    size_t read(uint8_t *buf, size_t len);
    size_t write(const uint8_t *buf, size_t len);
    void close();
    const char *name() const;
    File openNextFile();
    time_t getLastWrite() const;

private:
    std::shared_ptr<FileImpl> impl_;
};

class LittleFSClass {
public:
    std::string root;           // the host folder
    bool begin(bool format_on_fail = false);
    File open(const String &path, const char *mode = "r");
    bool exists(const String &path);
    bool mkdir(const String &path);
    bool rmdir(const String &path);
    bool remove(const String &path);
    bool rename(const String &from, const String &to);
    size_t totalBytes();
    size_t usedBytes();
};

extern LittleFSClass LittleFS;
