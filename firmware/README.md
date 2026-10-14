# WiC64 firmware for the desktop

Firmware for a [WiC64](https://wic64.net/web/) (an ESP32 on the C64's user
port) that makes it the desktop's file server, as Frodo's emulated WiC64 is:

- **Volume 0, the WiC64's flash** (LittleFS, 2.4 MB): the startup disk, with
  the System Folder and the applications. It is always there, network or not.
- **Volumes 1 to 6, network shares** (SMB 2 and 3, as from Windows, a Mac, a
  NAS or Samba), set up on the WiC64's web page. Each is a disk on the C64's
  desktop; it is connected when its icon is opened.
- The file service the System uses ([../docs/fileservice.md](../docs/fileservice.md)),
  over the WiC64's own transfer protocol, on the same pins and with the same
  handshake as the official firmware. A few of the standard commands are
  there too (`$00` version, `$06` IP address, `$10` SSID, `$2A` status
  message, `$FE` echo).

This **replaces** the WiC64's own firmware: other WiC64 programs (which use
its HTTP and TCP commands) won't work while it is installed. To go back,
flash the official firmware again from [wic64.net](https://wic64.net/web/).

It has been tested against a simulated C64 on the host (below), not yet on a
real WiC64.

## Building and flashing

You need [PlatformIO](https://platformio.org/) (`pip install platformio`, or
the VS Code extension). Unplug the WiC64 from the C64 and connect its USB
port to the computer, then:

```sh
cd firmware
pio run -t upload       # build and flash the firmware
pio run -t uploadfs     # write ../flash (the startup disk) to the WiC64's flash
pio device monitor      # its log, at 115200 baud
```

The first build fetches [libsmb2](https://github.com/sahlberg/libsmb2)
(LGPL-2.1) into `lib/libsmb2/libsmb2`, at a fixed commit.

`uploadfs` replaces everything on the flash with the contents of the
project's `flash/` folder (`../build.sh` puts the System and the
applications there). The settings are kept apart, so they survive both
commands.

## Setting it up

1. Plug the WiC64 into the C64 and switch on. With no Wi-Fi settings yet, it
   opens its own Wi-Fi network, **WiC64-Setup**. Join it and open
   <http://192.168.4.1/>.
2. Enter your Wi-Fi network and password, the time zone (for the dates of
   files) and the shares, then **Save and restart**.
3. From then on the page is at <http://wic64.local/> (the host name can be
   changed), or at the address the log shows.

If the WiC64 can't join the network within 15 seconds, it opens WiC64-Setup
again. Holding the WiC64's button while switching on does the same.

The **Flash** page lists the flash, takes uploads into any folder, makes new
folders and deletes, so the System can be updated without a USB cable.

## Shares

For each share: a name for the desktop, the server (a host name or IP
address, with `:port` if not 445), the share's name on the server, and a
user and password (leave the user empty to log in as a guest).

- **Windows:** share a folder (its Properties → Sharing → Advanced Sharing),
  and use a Windows account and its password.
- **macOS:** System Settings → General → Sharing → File Sharing; under
  Options, turn on SMB and Windows File Sharing for your account. The share
  is the shared folder's name.
- **A NAS or Samba:** as set up there. Servers that only speak SMB 1 won't
  work.

## Limits

- Paths on the flash are at most 63 characters.
- Names that aren't printable ASCII show on the C64 with `?` in place of the
  other characters. Names starting with `.` are hidden.
- Reads are at most 64K at a time (the protocol's limit); the System reads
  whole files of up to 64K.
- The C64 waits about four seconds for each answer; a share that doesn't
  answer in time (say, a server that is asleep) gives an error on the C64.
- The web page has no password: anyone on your network can change the
  settings.

## Testing on the host

```sh
test/run.sh             # the transfer protocol and the flash volume
test/run.sh --smb       # and a network share (needs impacket: pip install impacket)
```

`test/c64sim.cpp` builds the firmware's user port driver, file service and
volumes on the host, with stand-ins for the Arduino core in `test/shim`
(the flash is a copy of `flash/`), and plays the C64's side of the
handshake exactly as `src/net.asm` does: each byte written to `$DD01`, a
wait for FLAG2, the turn round on PA2, the reads. It checks the protocol (a
response left unread, a request broken off, both sides never driving the
port at once) and every file service command on the flash and on an SMB
share served by impacket (`test/smbserver.py`, which corrects two ways in
which impacket's replies differ from real servers).

## The source

| File | |
|---|---|
| `src/main.cpp` | Start-up, and the main loop: take a request, answer it |
| `src/userport.cpp` | The transfer protocol, in the PC2 and PA2 interrupts |
| `src/fileservice.cpp` | The commands, as in Frodo's `WiC64.cpp` |
| `src/flash_volume.cpp` | Volume 0, on LittleFS |
| `src/smb_volume.cpp` | A network share, with libsmb2 (reconnects if the server drops it) |
| `src/settings.cpp` | The settings, in the ESP32's NVS |
| `src/webui.cpp` | Wi-Fi, the setup page and the flash page |
| `partitions.csv` | 1.5 MB for the firmware, 2.4 MB for the flash volume |
