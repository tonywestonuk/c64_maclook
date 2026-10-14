// volume.h - the volumes the file service offers the C64
//
// Volume 0 is the WiC64's own flash (LittleFS), the startup disk; the
// others are network shares (SMB).  Paths given to a volume are
// relative to its root, with '/' between names and no leading '/'
// ("" is the root); the file service has checked them already.
// Calls return a file service status (0 = success, see fileservice.h)
// and leave a message in `error` when they fail.

#pragma once
#include <Arduino.h>
#include <vector>

struct Entry {
    String name;
    bool dir;
    uint32_t size;
    uint16_t date;      // DOS/FAT: year-1980 (7 bits), month (4), day (5)
};

class Volume {
public:
    String name;        // as the C64 shows it
    bool network = false;
    String error;       // the message of the last failure

    virtual ~Volume() {}

    virtual bool connected() = 0;
    virtual int connect() { return 0; }
    virtual void disconnect() {}
    virtual void space(uint64_t &total_kb, uint64_t &free_kb) = 0;

    virtual int stat(const String &path, Entry &e) = 0;
    virtual int list(const String &path, std::vector<Entry> &out) = 0;
    // Up to len bytes at off; got = how many there were
    virtual int read(const String &path, uint32_t off, uint8_t *buf, uint32_t len, uint32_t &got) = 0;
    // mode: 0 create/replace, 1 at off into an existing file, 2 append
    virtual int write(const String &path, int mode, uint32_t off, const uint8_t *data, uint32_t len) = 0;
    virtual int remove(const String &path) = 0;          // a file or an empty folder
    virtual int rename(const String &from, const String &to) = 0;
    virtual int mkdir(const String &path) = 0;

protected:
    int fail(int status, const String &message)
    {
        error = message;
        return status;
    }
};

// Status codes (docs/fileservice.md)
enum {
    ST_OK = 0,
    ST_INTERNAL = 1,
    ST_CLIENT = 2,
    ST_NOT_FOUND = 16,
    ST_EXISTS = 17,
    ST_NOT_EMPTY = 18,
    ST_WRONG_KIND = 19,
    ST_BAD_REQUEST = 20,
    ST_NO_SHARE = 21,
    ST_IO = 22,
    ST_FULL = 23,
    ST_DENIED = 24,
};

// A Unix time as a DOS/FAT date, in the configured time zone (0 if the
// clock was not set)
uint16_t fat_date(time_t t);

// An errno as a status
int status_of_errno(int e);

// The volumes: the flash first, then the shares from the settings
Volume *make_flash_volume(const String &name);
Volume *make_smb_volume(const String &name, const String &server, const String &share,
                        const String &user, const String &password, const String &domain);
