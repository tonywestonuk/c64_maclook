// smb_volume.cpp - a network share (SMB 2/3, as from Windows, a Mac or
// a NAS), with libsmb2's synchronous calls
//
// The C64 connects a share when it opens its icon; the connection is
// kept, checked with an echo when it has been idle a while or a call
// failed for want of the server, and made again if the server dropped
// it.

#include "volume.h"
#include <fcntl.h>
#include <errno.h>
#include <algorithm>

extern "C" {
#include <smb2/smb2.h>
#include <smb2/libsmb2.h>
}

class SmbVolume : public Volume {
public:
    SmbVolume(const String &n, const String &srv, const String &shr,
              const String &usr, const String &pwd, const String &dom)
        : server(srv), share(shr), user(usr), password(pwd), domain(dom)
    {
        name = n;
        network = true;
    }

    ~SmbVolume() override { disconnect(); }

    bool connected() override { return smb2 != nullptr; }

    int connect() override
    {
        if (smb2) {
            return alive() ? ST_OK : reconnect();
        }
        return open_session();
    }

    void disconnect() override
    {
        if (smb2) {
            smb2_disconnect_share(smb2);
            smb2_destroy_context(smb2);
            smb2 = nullptr;
        }
    }

    void space(uint64_t &total_kb, uint64_t &free_kb) override
    {
        total_kb = free_kb = 0;
        if (!sizes || ready()) {
            return;
        }
        struct smb2_statvfs vfs;
        if (smb2_statvfs(smb2, "", &vfs) < 0) {
            sizes = false;          // a server that cannot say: don't ask again
            suspect = true;
            return;
        }
        uint64_t unit = vfs.f_frsize ? vfs.f_frsize : vfs.f_bsize;
        total_kb = vfs.f_blocks * unit / 1024;
        free_kb = vfs.f_bavail * unit / 1024;
    }

    int stat(const String &path, Entry &e) override
    {
        if (int st = ready()) {
            return st;
        }
        struct smb2_stat_64 s;
        int r = smb2_stat(smb2, path.c_str(), &s);
        if (r < 0) {
            return smb_fail(r, "No such file or folder");
        }
        e.name = path;
        e.dir = s.smb2_type == SMB2_TYPE_DIRECTORY;
        e.size = e.dir ? 0 : (uint32_t)std::min<uint64_t>(s.smb2_size, 0xffffffff);
        e.date = fat_date((time_t)s.smb2_mtime);
        return ST_OK;
    }

    int list(const String &path, std::vector<Entry> &out) override
    {
        if (int st = ready()) {
            return st;
        }
        struct smb2_stat_64 s;
        int r = smb2_stat(smb2, path.c_str(), &s);
        if (r < 0) {
            return smb_fail(r, "No such folder");
        }
        if (s.smb2_type != SMB2_TYPE_DIRECTORY) {
            return fail(ST_WRONG_KIND, "Not a folder");
        }
        struct smb2dir *dir = smb2_opendir(smb2, path.c_str());
        if (!dir) {
            suspect = true;
            return fail(ST_IO, smb2_get_error(smb2));
        }
        while (struct smb2dirent *de = smb2_readdir(smb2, dir)) {
            if (!strcmp(de->name, ".") || !strcmp(de->name, "..")) {
                continue;
            }
            Entry e;
            e.name = de->name;
            e.dir = de->st.smb2_type == SMB2_TYPE_DIRECTORY;
            e.size = e.dir ? 0 : (uint32_t)std::min<uint64_t>(de->st.smb2_size, 0xffffffff);
            e.date = fat_date((time_t)de->st.smb2_mtime);
            out.push_back(e);
        }
        smb2_closedir(smb2, dir);
        return ST_OK;
    }

    int read(const String &path, uint32_t off, uint8_t *buf, uint32_t len, uint32_t &got) override
    {
        got = 0;
        if (int st = ready()) {
            return st;
        }
        struct smb2fh *fh = smb2_open(smb2, path.c_str(), O_RDONLY);
        if (!fh) {
            return open_fail(path);
        }
        uint32_t chunk = std::max<uint32_t>(smb2_get_max_read_size(smb2), 4096);
        while (got < len) {
            int r = smb2_pread(smb2, fh, buf + got, std::min(len - got, chunk), (uint64_t)off + got);
            if (r < 0) {
                smb2_close(smb2, fh);
                return smb_fail(r, "Read failed");
            }
            if (r == 0) {
                break;
            }
            got += r;
        }
        smb2_close(smb2, fh);
        return ST_OK;
    }

    int write(const String &path, int mode, uint32_t off, const uint8_t *data, uint32_t len) override
    {
        if (int st = ready()) {
            return st;
        }
        struct smb2_stat_64 s;
        bool exists = smb2_stat(smb2, path.c_str(), &s) == 0;
        if (exists && s.smb2_type == SMB2_TYPE_DIRECTORY) {
            return fail(ST_WRONG_KIND, "That is a folder");
        }
        int flags;
        uint64_t at = off;
        if (mode == 0) {
            flags = O_WRONLY | O_CREAT | O_TRUNC;
            at = 0;
        } else if (mode == 1) {
            if (!exists) {
                return fail(ST_NOT_FOUND, "No such file");
            }
            flags = O_WRONLY;
        } else if (mode == 2) {
            flags = O_WRONLY | O_CREAT;
            at = exists ? s.smb2_size : 0;
        } else {
            return fail(ST_BAD_REQUEST, "Bad write mode");
        }
        struct smb2fh *fh = smb2_open(smb2, path.c_str(), flags);
        if (!fh) {
            return open_fail(path);
        }
        uint32_t chunk = std::max<uint32_t>(smb2_get_max_write_size(smb2), 4096);
        uint32_t done = 0;
        while (done < len) {
            int r = smb2_pwrite(smb2, fh, data + done, std::min(len - done, chunk), at + done);
            if (r <= 0) {
                smb2_close(smb2, fh);
                return smb_fail(r ? r : -EIO, "Write failed");
            }
            done += r;
        }
        smb2_close(smb2, fh);
        return ST_OK;
    }

    int remove(const String &path) override
    {
        if (int st = ready()) {
            return st;
        }
        struct smb2_stat_64 s;
        int r = smb2_stat(smb2, path.c_str(), &s);
        if (r < 0) {
            return smb_fail(r, "No such file or folder");
        }
        if (s.smb2_type == SMB2_TYPE_DIRECTORY) {
            // (some servers would remove a full folder, contents and all)
            struct smb2dir *dir = smb2_opendir(smb2, path.c_str());
            if (!dir) {
                suspect = true;
                return fail(ST_IO, smb2_get_error(smb2));
            }
            bool empty = true;
            while (struct smb2dirent *de = smb2_readdir(smb2, dir)) {
                if (strcmp(de->name, ".") && strcmp(de->name, "..")) {
                    empty = false;
                    break;
                }
            }
            smb2_closedir(smb2, dir);
            if (!empty) {
                return fail(ST_NOT_EMPTY, "The folder is not empty");
            }
            r = smb2_rmdir(smb2, path.c_str());
            return r < 0 ? smb_fail(r, "Cannot remove the folder") : ST_OK;
        }
        r = smb2_unlink(smb2, path.c_str());
        return r < 0 ? smb_fail(r, "Cannot delete the file") : ST_OK;
    }

    int rename(const String &from, const String &to) override
    {
        if (int st = ready()) {
            return st;
        }
        struct smb2_stat_64 s;
        int r = smb2_stat(smb2, from.c_str(), &s);
        if (r < 0) {
            return smb_fail(r, "No such file or folder");
        }
        if (smb2_stat(smb2, to.c_str(), &s) == 0) {
            return fail(ST_EXISTS, "The name is already taken");
        }
        r = smb2_rename(smb2, from.c_str(), to.c_str());
        return r < 0 ? smb_fail(r, "Cannot rename it") : ST_OK;
    }

    int mkdir(const String &path) override
    {
        if (int st = ready()) {
            return st;
        }
        struct smb2_stat_64 s;
        if (smb2_stat(smb2, path.c_str(), &s) == 0) {
            return fail(ST_EXISTS, "The name is already taken");
        }
        int r = smb2_mkdir(smb2, path.c_str());
        return r < 0 ? smb_fail(r, "Cannot make the folder") : ST_OK;
    }

private:
    String server, share, user, password, domain;
    struct smb2_context *smb2 = nullptr;
    uint32_t last_used = 0;
    bool suspect = false;       // a call failed: is the connection still there?
    bool sizes = true;          // the server answers statvfs

    static const uint32_t IDLE_CHECK_MS = 30000;
    static const int TIMEOUT_S = 3;     // the C64 waits about four seconds

    int open_session()
    {
        smb2 = smb2_init_context();
        if (!smb2) {
            return fail(ST_INTERNAL, "Out of memory");
        }
        smb2_set_security_mode(smb2, SMB2_NEGOTIATE_SIGNING_ENABLED);
        smb2_set_timeout(smb2, TIMEOUT_S);
        if (password.length()) {
            smb2_set_password(smb2, password.c_str());
        }
        if (domain.length()) {
            smb2_set_domain(smb2, domain.c_str());
        }
        const char *u = user.length() ? user.c_str() : "guest";
        smb2_set_user(smb2, u);
        if (smb2_connect_share(smb2, server.c_str(), share.c_str(), u) < 0) {
            String why = smb2_get_error(smb2);
            smb2_destroy_context(smb2);
            smb2 = nullptr;
            return fail(ST_NO_SHARE, "Cannot connect: " + why);
        }
        last_used = millis();
        suspect = false;
        return ST_OK;
    }

    // Still there?  (An echo, if it has been idle a while or a call failed)
    bool alive()
    {
        if (!suspect && millis() - last_used < IDLE_CHECK_MS) {
            return true;
        }
        if (smb2_echo(smb2) < 0) {
            return false;
        }
        last_used = millis();
        suspect = false;
        return true;
    }

    int reconnect()
    {
        disconnect();
        return open_session();
    }

    // Connected (again, if the server dropped us)?  0 if so.
    int ready()
    {
        if (!smb2) {
            return fail(ST_NO_SHARE, "The share is not connected");
        }
        if (!alive()) {
            if (int st = reconnect()) {
                return st;
            }
        }
        last_used = millis();
        return ST_OK;
    }

    int smb_fail(int r, const char *what)
    {
        int st = status_of_errno(r);
        if (st == ST_IO) {
            suspect = true;
            return fail(st, String(what) + ": " + smb2_get_error(smb2));
        }
        return fail(st, what);
    }

    int open_fail(const String &path)
    {
        struct smb2_stat_64 s;
        int r = smb2_stat(smb2, path.c_str(), &s);
        if (r < 0) {
            return smb_fail(r, "No such file");
        }
        if (s.smb2_type == SMB2_TYPE_DIRECTORY) {
            return fail(ST_WRONG_KIND, "That is a folder");
        }
        return fail(ST_DENIED, "Cannot open the file");
    }
};

Volume *make_smb_volume(const String &name, const String &server, const String &share,
                        const String &user, const String &password, const String &domain)
{
    return new SmbVolume(name, server, share, user, password, domain);
}
