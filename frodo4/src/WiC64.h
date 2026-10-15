/*
 *  WiC64.h - WiC64 network adapter on the user port
 *
 *  Emulates a WiC64 (an ESP32 on the user port) speaking the WiC64
 *  transfer protocol, with a few of its standard commands, the file
 *  service of the C64 Mac-look desktop (docs/fileservice.md) and its
 *  matrix unit (docs/npu.md).  Its volumes are folders on the host: the
 *  internal flash (volume 0) and network shares (1 and up).
 */

#ifndef WIC64_H
#define WIC64_H

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include "../../npu/npu.h"

class MOS6526_2;
class Prefs;


class WiC64 {
public:
	WiC64(MOS6526_2 * cia);

	void Reset();
	void NewPrefs(const Prefs * prefs);
	bool Enabled() const { return enabled; }

	// The C64's cycle counter: the matrix unit's clock (C64 time)
	void SetCycleClock(std::function<uint32_t()> cycles);

	// Calls from CIA 2
	void SetPA2(bool high);				// PA2: high = C64 sends, low = C64 receives
	void PortBWritten(uint8_t byte);	// C64 wrote $dd01 (PC2 strobe)
	void PortBRead();					// C64 read $dd01 (PC2 strobe, after the read)
	uint8_t PortBIn() const;			// What the WiC64 drives on PB0-PB7

private:
	void handshake();
	void request_complete();
	void reply(uint8_t status, const std::vector<uint8_t> & data = {});
	void fail(uint8_t status, const std::string & message);

	// Commands
	void cmd_info(const uint8_t * p, size_t n);
	void cmd_volumes();
	void cmd_connect(const uint8_t * p, size_t n, bool connect);
	void cmd_list(const uint8_t * p, size_t n);
	void cmd_read(const uint8_t * p, size_t n);
	void cmd_write(const uint8_t * p, size_t n);
	void cmd_delete(const uint8_t * p, size_t n);
	void cmd_rename(const uint8_t * p, size_t n, bool copy);
	void cmd_mkdir(const uint8_t * p, size_t n);
	void cmd_stat(const uint8_t * p, size_t n);
	void cmd_npu(const uint8_t * p, size_t n);

	bool host_path(const std::string & rel, std::string & out, int * vol = nullptr);
	bool volume_ready(int vol);

	MOS6526_2 * the_cia;

	bool enabled = false;

	struct Volume {
		std::string name;			// As the C64 shows it
		std::string path;			// Host folder
		bool network;				// A share (else the internal flash)
		bool connected;
	};
	std::vector<Volume> volumes;

	enum { IDLE, RECEIVING, RESPONDING } state = IDLE;
	bool pa2 = true;
	uint8_t pb_out = 0xff;

	std::vector<uint8_t> request;	// Header and payload as received
	size_t request_size = 0;		// Expected total size (0 = header not complete)
	uint8_t protocol = 0;
	uint8_t command = 0;
	size_t header_size = 0;

	std::vector<uint8_t> response;	// Header and payload to send
	size_t response_pos = 0;
	bool response_ready = false;

	std::string status_message;

	Npu npu{65536};					// The matrix unit
	uint64_t clock_cycles = 0;		// C64 cycles counted for its clock
	uint32_t clock_last = 0;
};


#endif
