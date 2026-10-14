/*
 *  WiC64.cpp - WiC64 network adapter on the user port
 *
 *  Part of the C64 Mac-look desktop's patches to Frodo (GPL-2.0, like
 *  Frodo).  See WiC64.h and docs/fileservice.md.
 *
 *  The WiC64 transfer protocol, as the real firmware does it:
 *  - PA2 high: the C64 sends.  Each write to $dd01 strobes PC2; the
 *    WiC64 takes the byte and acknowledges on FLAG2 (CIA 2 ICR bit 4).
 *  - PA2 low: the C64 receives.  The WiC64 acknowledges the change of
 *    direction on FLAG2.  Each read of $dd01 strobes PC2; the WiC64 puts
 *    the next byte on the port and signals FLAG2.
 *  Requests: 'R' cmd size(2) payload, or 'E' cmd size(4) payload.
 *  Responses: status size(2 or 4) payload.
 */

#include "sysdeps.h"

#include "WiC64.h"
#include "CIA.h"
#include "Prefs.h"

#include <algorithm>
#include <chrono>
#include <ctime>
#include <filesystem>
#include <fstream>
#include <system_error>

namespace fs = std::filesystem;


// Status codes: WiC64 standard ones, then the file service's
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


WiC64::WiC64(MOS6526_2 * cia) : the_cia(cia)
{
	Reset();
}


void WiC64::Reset()
{
	state = IDLE;
	pa2 = true;
	pb_out = 0xff;
	request.clear();
	request_size = 0;
	response.clear();
	response_pos = 0;
	response_ready = false;
}


void WiC64::NewPrefs(const Prefs * prefs)
{
	enabled = prefs->WiC64;

	// Volume 0: the internal flash, the startup disk.  Then the shares,
	// "name=folder" or just "folder", separated by ';'.  Shares start
	// disconnected; the C64 connects them (as the real WiC64 logs in).
	volumes.clear();
	volumes.push_back({"System Disk", prefs->WiC64Flash, false, true});
	std::string list = prefs->WiC64Share;
	size_t start = 0;
	while (start < list.size()) {
		size_t end = list.find(';', start);
		if (end == std::string::npos) {
			end = list.size();
		}
		std::string item = list.substr(start, end - start);
		if (!item.empty()) {
			std::string name, path = item;
			size_t eq = item.find('=');
			if (eq != std::string::npos) {
				name = item.substr(0, eq);
				path = item.substr(eq + 1);
			} else {
				name = fs::path(path).lexically_normal().filename().string();
				if (name.empty()) {
					name = fs::path(path).lexically_normal().parent_path().filename().string();
				}
			}
			volumes.push_back({name, path, true, false});
		}
		start = end + 1;
	}
}


/*
 *  The user port
 */

void WiC64::handshake()
{
	the_cia->TriggerFlagLine();
}

void WiC64::SetPA2(bool high)
{
	if (high == pa2) {
		return;
	}
	pa2 = high;
	if (!enabled) {
		return;
	}

	if (high) {				// The C64 starts sending a request
		state = RECEIVING;
		request.clear();
		request_size = 0;
		response_ready = false;
	} else if (response_ready) {	// The C64 is ready for the response
		state = RESPONDING;
		response_pos = 0;
		handshake();
	}
}

void WiC64::PortBWritten(uint8_t byte)
{
	if (!enabled || !pa2) {
		return;
	}
	if (state != RECEIVING) {
		state = RECEIVING;
		request.clear();
		request_size = 0;
	}

	request.push_back(byte);
	if (request.size() == 1) {
		protocol = byte;
		if (protocol == 'R') {
			header_size = 4;
		} else if (protocol == 'E') {
			header_size = 6;
		} else {			// Not a protocol we know (e.g. legacy 'W'): ignore
			request.clear();
			handshake();
			return;
		}
	}
	if (request_size == 0 && request.size() == header_size) {
		command = request[1];
		size_t payload = request[2] | (request[3] << 8);
		if (protocol == 'E') {
			payload |= (request[4] << 16) | (size_t(request[5]) << 24);
		}
		request_size = header_size + payload;
	}

	handshake();			// Acknowledge the byte

	if (request_size && request.size() == request_size) {
		request_complete();
	}
}

void WiC64::PortBRead()
{
	if (!enabled || pa2 || state != RESPONDING) {
		return;
	}
	if (response_pos < response.size()) {
		pb_out = response[response_pos++];
		handshake();
	} else {
		state = IDLE;		// All sent
	}
}

uint8_t WiC64::PortBIn() const
{
	return (enabled && !pa2) ? pb_out : 0xff;
}


/*
 *  Requests and responses
 */

void WiC64::reply(uint8_t status, const std::vector<uint8_t> & data)
{
	size_t size = data.size();
	if (protocol != 'E' && size > 0xffff) {
		size = 0xffff;
	}
	response.clear();
	response.push_back(status);
	response.push_back(size & 0xff);
	response.push_back((size >> 8) & 0xff);
	if (protocol == 'E') {
		response.push_back((size >> 16) & 0xff);
		response.push_back((size >> 24) & 0xff);
	}
	response.insert(response.end(), data.begin(), data.begin() + size);
	response_pos = 0;
	response_ready = true;
	state = IDLE;
}

void WiC64::fail(uint8_t status, const std::string & message)
{
	status_message = message;
	reply(status);
}

static std::vector<uint8_t> bytes_of(const std::string & s)
{
	return std::vector<uint8_t>(s.begin(), s.end());
}

static uint32_t get32(const uint8_t * p)
{
	return p[0] | (p[1] << 8) | (p[2] << 16) | (uint32_t(p[3]) << 24);
}

static void put32(std::vector<uint8_t> & v, uint32_t x)
{
	v.push_back(x & 0xff);
	v.push_back((x >> 8) & 0xff);
	v.push_back((x >> 16) & 0xff);
	v.push_back((x >> 24) & 0xff);
}

static std::string string_of(const uint8_t * p, size_t n)
{
	std::string s(reinterpret_cast<const char *>(p), n);
	size_t end = s.find('\0');
	if (end != std::string::npos) {
		s.resize(end);
	}
	return s;
}

// A host file name as the C64 sees it: printable ASCII only
static std::string c64_name(const std::string & name)
{
	std::string out;
	for (unsigned char c : name) {
		out += (c >= 32 && c < 127 && c != '/' && c != ':') ? char(c) : '?';
	}
	return out;
}

void WiC64::request_complete()
{
	const uint8_t * p = request.data() + header_size;
	size_t n = request.size() - header_size;

	status_message = "Success";
	switch (command) {

		// A few of the WiC64's standard commands
		case 0x00:	// Version string
			reply(ST_OK, bytes_of("WiC64 (emulated by Frodo) file service 1.0"));
			break;
		case 0x26:	// Version numbers: major, minor, patch, development
			reply(ST_OK, {2, 0, 0, 0});
			break;
		case 0x06:	// IP address
			reply(ST_OK, bytes_of("127.0.0.1"));
			break;
		case 0x10:	// SSID
			reply(ST_OK, bytes_of("Frodo"));
			break;
		case 0x2c:	// Connected?
		case 0x2f:	// Configured?
		case 0x2d:	// Set transfer timeout
		case 0x32:	// Set remote timeout
			reply(ST_OK);
			break;
		case 0x2a:	// Status message of the last request
			reply(ST_OK, bytes_of(status_message));
			break;
		case 0xfe:	// Echo
			reply(ST_OK, std::vector<uint8_t>(p, p + n));
			break;

		// The file service
		case 0x80: cmd_info(p, n); break;
		case 0x81: cmd_list(p, n); break;
		case 0x82: cmd_read(p, n); break;
		case 0x83: cmd_write(p, n); break;
		case 0x84: cmd_delete(p, n); break;
		case 0x85: cmd_rename(p, n, false); break;
		case 0x86: cmd_mkdir(p, n); break;
		case 0x87: cmd_stat(p, n); break;
		case 0x88: cmd_rename(p, n, true); break;
		case 0x89: cmd_volumes(); break;
		case 0x8a: cmd_connect(p, n, true); break;
		case 0x8b: cmd_connect(p, n, false); break;

		default:
			fail(ST_CLIENT, "Undefined command");
			break;
	}
}


/*
 *  The file service, on a host folder
 */

static uint8_t status_of(const std::error_code & ec)
{
	if (ec == std::errc::no_such_file_or_directory) return ST_NOT_FOUND;
	if (ec == std::errc::file_exists) return ST_EXISTS;
	if (ec == std::errc::directory_not_empty) return ST_NOT_EMPTY;
	if (ec == std::errc::is_a_directory || ec == std::errc::not_a_directory) return ST_WRONG_KIND;
	if (ec == std::errc::permission_denied || ec == std::errc::operation_not_permitted) return ST_DENIED;
	if (ec == std::errc::no_space_on_device) return ST_FULL;
	return ST_IO;
}

// Is volume vol there and connected?  (If not, a reply is sent.)
bool WiC64::volume_ready(int vol)
{
	if (vol < 0 || vol >= int(volumes.size())) {
		fail(ST_NO_SHARE, "No such volume");
		return false;
	}
	if (!volumes[vol].connected) {
		fail(ST_NO_SHARE, "The share is not connected");
		return false;
	}
	if (volumes[vol].path.empty() || !fs::is_directory(volumes[vol].path)) {
		fail(ST_NO_SHARE, "The volume is not available");
		return false;
	}
	return true;
}

// "n:path" (or "path", on volume 0) -> host path.  False (and a reply
// sent) if not allowed.
bool WiC64::host_path(const std::string & full, std::string & out, int * vol_out)
{
	int vol = 0;
	std::string rel = full;
	if (rel.size() >= 2 && rel[0] >= '0' && rel[0] <= '9' && rel[1] == ':') {
		vol = rel[0] - '0';
		rel = rel.substr(2);
	}
	if (!volume_ready(vol)) {
		return false;
	}
	fs::path p(volumes[vol].path);
	size_t start = 0;
	while (start <= rel.size()) {
		size_t end = rel.find('/', start);
		if (end == std::string::npos) {
			end = rel.size();
		}
		std::string part = rel.substr(start, end - start);
		if (part == "." || part == ".." || part.find(':') != std::string::npos ||
		    part.find('\\') != std::string::npos) {
			fail(ST_BAD_REQUEST, "Bad path");
			return false;
		}
		if (!part.empty()) {
			p /= part;
		}
		start = end + 1;
	}
	out = p.string();
	if (vol_out) {
		*vol_out = vol;
	}
	return true;
}

// Last change of a host file, DOS/FAT style: year-1980 (7 bits), month, day
static uint16_t fat_date(const std::string & path)
{
	std::error_code ec;
	auto ft = fs::last_write_time(path, ec);
	if (ec) {
		return 0;
	}
	auto st = std::chrono::time_point_cast<std::chrono::system_clock::duration>(
		ft - fs::file_time_type::clock::now() + std::chrono::system_clock::now());
	std::time_t t = std::chrono::system_clock::to_time_t(st);
	std::tm * tm = std::localtime(&t);
	if (!tm || tm->tm_year < 80) {
		return 0;
	}
	return ((tm->tm_year - 80) << 9) | ((tm->tm_mon + 1) << 5) | tm->tm_mday;
}

void WiC64::cmd_info(const uint8_t * p, size_t n)
{
	int vol = n ? p[0] : 0;
	if (!volume_ready(vol)) {
		return;
	}
	std::error_code ec;
	fs::space_info si = fs::space(volumes[vol].path, ec);
	std::vector<uint8_t> out;
	uint64_t total = ec ? 0 : si.capacity / 1024, avail = ec ? 0 : si.available / 1024;
	put32(out, uint32_t(std::min<uint64_t>(total, 0xffffffff)));
	put32(out, uint32_t(std::min<uint64_t>(avail, 0xffffffff)));
	auto nb = bytes_of(c64_name(volumes[vol].name));
	out.insert(out.end(), nb.begin(), nb.end());
	reply(ST_OK, out);
}

void WiC64::cmd_volumes()
{
	std::vector<uint8_t> out;
	out.push_back(uint8_t(volumes.size()));
	for (size_t i = 0; i < volumes.size(); ++i) {
		const Volume & v = volumes[i];
		bool up = v.connected && !v.path.empty() && fs::is_directory(v.path);
		uint64_t total = 0, avail = 0;
		if (up) {
			std::error_code ec;
			fs::space_info si = fs::space(v.path, ec);
			if (!ec) {
				total = si.capacity / 1024;
				avail = si.available / 1024;
			}
		}
		out.push_back(uint8_t(i));
		out.push_back(v.network ? 1 : 0);
		out.push_back(up ? 1 : 0);
		put32(out, uint32_t(std::min<uint64_t>(total, 0xffffffff)));
		put32(out, uint32_t(std::min<uint64_t>(avail, 0xffffffff)));
		std::string name = c64_name(v.name).substr(0, 255);
		out.push_back(uint8_t(name.size()));
		out.insert(out.end(), name.begin(), name.end());
	}
	reply(ST_OK, out);
}

void WiC64::cmd_connect(const uint8_t * p, size_t n, bool connect)
{
	int vol = n ? p[0] : -1;
	if (vol < 0 || vol >= int(volumes.size())) {
		fail(ST_NO_SHARE, "No such volume");
		return;
	}
	Volume & v = volumes[vol];
	if (!v.network) {					// the flash is always there
		reply(ST_OK);
		return;
	}
	if (connect) {
		if (v.path.empty() || !fs::is_directory(v.path)) {
			fail(ST_NO_SHARE, "The share could not be reached");
			return;
		}
		v.connected = true;
	} else {
		v.connected = false;
	}
	reply(ST_OK);
}

void WiC64::cmd_list(const uint8_t * p, size_t n)
{
	if (n < 3) {
		fail(ST_BAD_REQUEST, "Bad request");
		return;
	}
	unsigned first = p[0] | (p[1] << 8);
	unsigned max = p[2];
	std::string path;
	if (!host_path(string_of(p + 3, n - 3), path)) {
		return;
	}
	std::error_code ec;
	if (!fs::is_directory(path, ec)) {
		fail(fs::exists(path) ? ST_WRONG_KIND : ST_NOT_FOUND, "Not a folder");
		return;
	}

	struct Entry { std::string name; bool dir; uint32_t size; uint16_t date; };
	std::vector<Entry> entries;
	for (const auto & de : fs::directory_iterator(path, ec)) {
		std::string name = de.path().filename().string();
		if (name.empty() || name[0] == '.') {
			continue;
		}
		std::error_code ec2;
		bool dir = de.is_directory(ec2);
		uint64_t size = dir ? 0 : de.file_size(ec2);
		entries.push_back({c64_name(name), dir, uint32_t(std::min<uint64_t>(size, 0xffffffff)),
		                   fat_date(de.path().string())});
	}
	if (ec) {
		fail(status_of(ec), ec.message());
		return;
	}
	std::sort(entries.begin(), entries.end(), [](const Entry & a, const Entry & b) {
		std::string x = a.name, y = b.name;
		std::transform(x.begin(), x.end(), x.begin(), ::tolower);
		std::transform(y.begin(), y.end(), y.begin(), ::tolower);
		return x < y;
	});

	std::vector<uint8_t> out;
	out.push_back(entries.size() & 0xff);
	out.push_back((entries.size() >> 8) & 0xff);
	out.push_back(0);		// count, filled in below
	unsigned count = 0;
	for (size_t i = first; i < entries.size() && count < max; ++i) {
		const Entry & e = entries[i];
		std::string name = e.name.substr(0, 255);
		if (out.size() + 9 + name.size() > 0xffff) {
			break;
		}
		out.push_back(e.dir ? 1 : 0);
		put32(out, e.size);
		out.push_back(e.date & 0xff);
		out.push_back(e.date >> 8);
		out.push_back(uint8_t(name.size()));
		out.insert(out.end(), name.begin(), name.end());
		++count;
	}
	out[2] = uint8_t(count);
	reply(ST_OK, out);
}

void WiC64::cmd_read(const uint8_t * p, size_t n)
{
	if (n < 6) {
		fail(ST_BAD_REQUEST, "Bad request");
		return;
	}
	uint32_t offset = get32(p);
	unsigned length = p[4] | (p[5] << 8);
	std::string path;
	if (!host_path(string_of(p + 6, n - 6), path)) {
		return;
	}
	if (fs::is_directory(path)) {
		fail(ST_WRONG_KIND, "That is a folder");
		return;
	}
	std::ifstream f(path, std::ios::binary);
	if (!f) {
		fail(fs::exists(path) ? ST_DENIED : ST_NOT_FOUND, "Cannot open the file");
		return;
	}
	std::vector<uint8_t> out(length);
	f.seekg(offset);
	f.read(reinterpret_cast<char *>(out.data()), length);
	out.resize(f.gcount() > 0 ? size_t(f.gcount()) : 0);
	reply(ST_OK, out);
}

void WiC64::cmd_write(const uint8_t * p, size_t n)
{
	if (n < 6 || n < 6u + p[5]) {
		fail(ST_BAD_REQUEST, "Bad request");
		return;
	}
	uint32_t offset = get32(p);
	uint8_t mode = p[4];
	size_t plen = p[5];
	std::string path;
	if (!host_path(string_of(p + 6, plen), path)) {
		return;
	}
	const char * data = reinterpret_cast<const char *>(p + 6 + plen);
	size_t size = n - 6 - plen;
	if (fs::is_directory(path)) {
		fail(ST_WRONG_KIND, "That is a folder");
		return;
	}

	std::fstream f;
	if (mode == 0) {
		f.open(path, std::ios::out | std::ios::binary | std::ios::trunc);
	} else if (mode == 1) {
		if (!fs::exists(path)) {
			fail(ST_NOT_FOUND, "No such file");
			return;
		}
		f.open(path, std::ios::in | std::ios::out | std::ios::binary);
		f.seekp(offset);
	} else if (mode == 2) {
		f.open(path, std::ios::out | std::ios::binary | std::ios::app);
	} else {
		fail(ST_BAD_REQUEST, "Bad write mode");
		return;
	}
	if (!f) {
		fail(fs::exists(fs::path(path).parent_path()) ? ST_DENIED : ST_NOT_FOUND, "Cannot write the file");
		return;
	}
	f.write(data, size);
	if (!f) {
		fail(ST_IO, "Write failed");
		return;
	}
	reply(ST_OK);
}

void WiC64::cmd_delete(const uint8_t * p, size_t n)
{
	std::string path;
	if (!host_path(string_of(p, n), path)) {
		return;
	}
	std::error_code ec;
	if (!fs::exists(path, ec)) {
		fail(ST_NOT_FOUND, "No such file or folder");
		return;
	}
	if (fs::is_directory(path, ec) && !fs::is_empty(path, ec)) {
		fail(ST_NOT_EMPTY, "The folder is not empty");
		return;
	}
	fs::remove(path, ec);
	if (ec) {
		fail(status_of(ec), ec.message());
		return;
	}
	reply(ST_OK);
}

void WiC64::cmd_rename(const uint8_t * p, size_t n, bool copy)
{
	if (n < 1 || n < 1u + p[0]) {
		fail(ST_BAD_REQUEST, "Bad request");
		return;
	}
	std::string from, to;
	int vol_from = 0, vol_to = 0;
	if (!host_path(string_of(p + 1, p[0]), from, &vol_from) ||
	    !host_path(string_of(p + 1 + p[0], n - 1 - p[0]), to, &vol_to)) {
		return;
	}
	if (!copy && vol_from != vol_to) {
		fail(ST_BAD_REQUEST, "Things can only be moved within a volume");
		return;
	}
	std::error_code ec;
	if (!fs::exists(from, ec)) {
		fail(ST_NOT_FOUND, "No such file or folder");
		return;
	}
	if (fs::exists(to, ec)) {
		fail(ST_EXISTS, "The name is already taken");
		return;
	}
	if (copy) {
		if (fs::is_directory(from, ec)) {
			fail(ST_WRONG_KIND, "Folders cannot be copied");
			return;
		}
		fs::copy_file(from, to, ec);
	} else {
		fs::rename(from, to, ec);
	}
	if (ec) {
		fail(status_of(ec), ec.message());
		return;
	}
	reply(ST_OK);
}

void WiC64::cmd_mkdir(const uint8_t * p, size_t n)
{
	std::string path;
	if (!host_path(string_of(p, n), path)) {
		return;
	}
	std::error_code ec;
	if (fs::exists(path, ec)) {
		fail(ST_EXISTS, "The name is already taken");
		return;
	}
	fs::create_directory(path, ec);
	if (ec) {
		fail(status_of(ec), ec.message());
		return;
	}
	reply(ST_OK);
}

void WiC64::cmd_stat(const uint8_t * p, size_t n)
{
	std::string path;
	if (!host_path(string_of(p, n), path)) {
		return;
	}
	std::error_code ec;
	if (!fs::exists(path, ec)) {
		fail(ST_NOT_FOUND, "No such file or folder");
		return;
	}
	std::vector<uint8_t> out;
	bool dir = fs::is_directory(path, ec);
	out.push_back(dir ? 1 : 0);
	put32(out, dir ? 0 : uint32_t(std::min<uintmax_t>(fs::file_size(path, ec), 0xffffffff)));
	uint16_t date = fat_date(path);
	out.push_back(date & 0xff);
	out.push_back(date >> 8);
	reply(ST_OK, out);
}
