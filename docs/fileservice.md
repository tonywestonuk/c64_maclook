# The network file service (WiC64 commands `$80`–`$88`)

The C64 reaches its files through a [WiC64](https://wic64.net/web/) on the user
port. The WiC64 (or Frodo's emulation of it) connects to a file share and offers
it to the C64 with the commands below. They use the WiC64's normal transfer
protocol, so they sit alongside its standard commands.

## Transport

The standard WiC64 protocol, unchanged:

```
request:   'R'  command  size-low  size-high   payload...
response:  status  size-low  size-high          payload...
```

The extended protocol (`'E'`, with 32-bit sizes) is accepted too. Lines on the
user port: data on PB0–PB7; PA2 high while the C64 sends, low while it
receives; the C64's reads and writes of `$DD01` strobe PC2, and the WiC64 answers
each byte on FLAG2 (bit 4 of `$DD0D`). See the
[WiC64 library](https://github.com/WiC64-Team/wic64-library) for the details.

## Conventions

- Numbers are little-endian.
- Paths are ASCII, with `/` between names and no leading `/`, relative to the
  root of the share. The empty path is the root.
- Names may hold the printable ASCII characters except `/` and `:`.
  Names starting with `.` are hidden from listings.
- Status `0` is success. Errors:

| Status | Meaning |
|---|---|
| 16 | not found |
| 17 | already exists |
| 18 | folder not empty |
| 19 | wrong kind (a folder where a file was expected, or the other way round) |
| 20 | bad request |
| 21 | the share isn't available |
| 22 | input/output error |
| 23 | the share is full |
| 24 | access denied |

  The text of the last error is available from the standard command `$2A`
  (get status message).

## Commands

| Command | Request payload | Response payload |
|---|---|---|
| `$80` info | | total KB (4), free KB (4), the share's name |
| `$81` list | first (2), max (1), path | total (2), count (1), then *count* entries: kind (1: 0 file, 1 folder), size (4), name length (1), name |
| `$82` read | offset (4), length (2), path | the bytes (fewer at the end of the file) |
| `$83` write | offset (4), mode (1), path length (1), path, data | |
| `$84` delete | path | |
| `$85` rename | length of *from* (1), from, to | |
| `$86` new folder | path | |
| `$87` details | path | kind (1), size (4) |
| `$88` copy | length of *from* (1), from, to | |

- **list** returns the entries of a folder sorted by name (ignoring case),
  starting at entry *first*, at most *max* of them; *total* is the number of
  entries in the folder.
- **write** modes: `0` creates the file or replaces its contents with *data*
  (*offset* is ignored); `1` writes *data* at *offset* into an existing file,
  extending it if needed; `2` appends *data*.
- **delete** removes a file or an empty folder.
- **rename** also moves an entry to another folder. *to* must not exist.
- **copy** copies a file; *to* must not exist.
