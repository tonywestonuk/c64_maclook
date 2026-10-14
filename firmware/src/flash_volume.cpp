// flash_volume.cpp - volume 0: the WiC64's flash, with LittleFS
//
// It holds the System Folder and the applications: the startup disk.
// `pio run -t uploadfs` writes the project's flash/ folder to it.

#include "volume.h"
#include <LittleFS.h>
#include <errno.h>

uint16_t fat_date(time_t t)
{
    if (t <= 0) {
        return 0;
    }
    struct tm tm;
    localtime_r(&t, &tm);
    if (tm.tm_year < 80) {      // the clock was not set (1970)
        return 0;
    }
    return ((tm.tm_year - 80) << 9) | ((tm.tm_mon + 1) << 5) | tm.tm_mday;
}

int status_of_errno(int e)
{
    if (e < 0) {
        e = -e;
    }
    switch (e) {
        case ENOENT:    return ST_NOT_FOUND;
        case EEXIST:    return ST_EXISTS;
        case ENOTEMPTY: return ST_NOT_EMPTY;
        case EISDIR:
        case ENOTDIR:   return ST_WRONG_KIND;
        case EACCES:
        case EPERM:
        case EROFS:     return ST_DENIED;
        case ENOSPC:    return ST_FULL;
        default:        return ST_IO;
    }
}

class FlashVolume : public Volume {
public:
    FlashVolume(const String &n)
    {
        name = n;
        network = false;
        mounted = LittleFS.begin(true);     // (formatted if it was empty)
    }

    bool connected() override { return mounted; }

    void space(uint64_t &total_kb, uint64_t &free_kb) override
    {
        total_kb = free_kb = 0;
        if (mounted) {
            total_kb = LittleFS.totalBytes() / 1024;
            free_kb = (LittleFS.totalBytes() - LittleFS.usedBytes()) / 1024;
        }
    }

    int stat(const String &path, Entry &e) override
    {
        String p = full(path);
        if (path.length() == 0) {
            e = {"", true, 0, 0};
            return ST_OK;
        }
        if (!LittleFS.exists(p)) {
            return fail(ST_NOT_FOUND, "No such file or folder");
        }
        File f = LittleFS.open(p);
        if (!f) {
            return fail(ST_IO, "Cannot open it");
        }
        e.name = leaf(path);
        e.dir = f.isDirectory();
        e.size = e.dir ? 0 : f.size();
        e.date = fat_date(f.getLastWrite());
        f.close();
        return ST_OK;
    }

    int list(const String &path, std::vector<Entry> &out) override
    {
        String p = full(path);
        File dir = LittleFS.open(p);
        if (!dir) {
            return fail(ST_NOT_FOUND, "No such folder");
        }
        if (!dir.isDirectory()) {
            dir.close();
            return fail(ST_WRONG_KIND, "Not a folder");
        }
        for (File f = dir.openNextFile(); f; f = dir.openNextFile()) {
            Entry e;
            e.name = leaf(f.name());
            e.dir = f.isDirectory();
            e.size = e.dir ? 0 : f.size();
            e.date = fat_date(f.getLastWrite());
            f.close();
            out.push_back(e);
        }
        dir.close();
        return ST_OK;
    }

    int read(const String &path, uint32_t off, uint8_t *buf, uint32_t len, uint32_t &got) override
    {
        got = 0;
        String p = full(path);
        if (!LittleFS.exists(p)) {
            return fail(ST_NOT_FOUND, "No such file");
        }
        File f = LittleFS.open(p, "r");
        if (!f) {
            return fail(ST_DENIED, "Cannot open the file");
        }
        if (f.isDirectory()) {
            f.close();
            return fail(ST_WRONG_KIND, "That is a folder");
        }
        if (off < f.size() && f.seek(off)) {
            got = f.read(buf, len);
        }
        f.close();
        return ST_OK;
    }

    int write(const String &path, int mode, uint32_t off, const uint8_t *data, uint32_t len) override
    {
        String p = full(path);
        bool exists = LittleFS.exists(p);
        if (exists && is_dir(p)) {
            return fail(ST_WRONG_KIND, "That is a folder");
        }
        if (!exists && !LittleFS.exists(parent(p))) {
            return fail(ST_NOT_FOUND, "No such folder");
        }
        const char *how = "w";
        if (mode == 1) {
            if (!exists) {
                return fail(ST_NOT_FOUND, "No such file");
            }
            how = "r+";
        } else if (mode == 2) {
            how = "a";
        } else if (mode != 0) {
            return fail(ST_BAD_REQUEST, "Bad write mode");
        }
        File f = LittleFS.open(p, how);
        if (!f) {
            return fail(ST_DENIED, "Cannot write the file");
        }
        if (mode == 1) {
            uint32_t size = f.size();
            if (off > size) {           // extend it with zeros
                f.seek(size);
                uint8_t zero[64] = {0};
                while (size < off) {
                    uint32_t n = min<uint32_t>(sizeof zero, off - size);
                    if (f.write(zero, n) != n) {
                        f.close();
                        return fail(ST_FULL, "The disk is full");
                    }
                    size += n;
                }
            } else {
                f.seek(off);
            }
        }
        size_t done = len ? f.write(data, len) : 0;
        f.close();
        if (done != len) {
            return fail(ST_FULL, "The disk is full");
        }
        return ST_OK;
    }

    int remove(const String &path) override
    {
        String p = full(path);
        if (path.length() == 0 || !LittleFS.exists(p)) {
            return fail(ST_NOT_FOUND, "No such file or folder");
        }
        if (is_dir(p)) {
            File dir = LittleFS.open(p);
            File f = dir.openNextFile();
            bool empty = !f;
            f.close();
            dir.close();
            if (!empty) {
                return fail(ST_NOT_EMPTY, "The folder is not empty");
            }
            return LittleFS.rmdir(p) ? ST_OK : fail(ST_IO, "Cannot remove the folder");
        }
        return LittleFS.remove(p) ? ST_OK : fail(ST_IO, "Cannot delete the file");
    }

    int rename(const String &from, const String &to) override
    {
        String a = full(from), b = full(to);
        if (from.length() == 0 || !LittleFS.exists(a)) {
            return fail(ST_NOT_FOUND, "No such file or folder");
        }
        if (to.length() == 0 || LittleFS.exists(b)) {
            return fail(ST_EXISTS, "The name is already taken");
        }
        if (!LittleFS.exists(parent(b))) {
            return fail(ST_NOT_FOUND, "No such folder");
        }
        if (b.startsWith(a + "/")) {
            return fail(ST_BAD_REQUEST, "A folder cannot go inside itself");
        }
        return LittleFS.rename(a, b) ? ST_OK : fail(ST_IO, "Cannot rename it");
    }

    int mkdir(const String &path) override
    {
        String p = full(path);
        if (path.length() == 0 || LittleFS.exists(p)) {
            return fail(ST_EXISTS, "The name is already taken");
        }
        if (!LittleFS.exists(parent(p))) {
            return fail(ST_NOT_FOUND, "No such folder");
        }
        return LittleFS.mkdir(p) ? ST_OK : fail(ST_IO, "Cannot make the folder");
    }

private:
    bool mounted;

    static String full(const String &path) { return "/" + path; }

    static String leaf(const String &path)
    {
        int slash = path.lastIndexOf('/');
        return slash < 0 ? path : path.substring(slash + 1);
    }

    static String parent(const String &p)
    {
        int slash = p.lastIndexOf('/');
        return slash <= 0 ? String("/") : p.substring(0, slash);
    }

    static bool is_dir(const String &p)
    {
        File f = LittleFS.open(p);
        bool dir = f && f.isDirectory();
        f.close();
        return dir;
    }
};

Volume *make_flash_volume(const String &name)
{
    return new FlashVolume(name);
}
