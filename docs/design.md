# Design

The library is sampled every second by a daemon for days, so the cost that matters is per
sample, and what must stay flat is memory.

| Decision | Why | Measured |
|---|---|---|
| Open every file once, keep the fds | a path lookup per file per sample is most of the Python cost | Python re-open 58 to 60 µs vs `pread` on kept fds 18 µs per 17 files |
| `pread(fd, buf, 256, 0)`, offset 0 | sysfs regenerates the attribute at offset 0, so no `lseek` and no reopen | 1 syscall per metric, about 470 ns |
| One 256-byte buffer in the struct | no heap block per read; every sysfs value here is under 100 bytes | `Gpu` is 488 bytes in total |
| Parse the bytes in place (`Span[UInt8]`) | no `String` per value | no allocation in `refresh()`; RSS 11.6 MB before and after 100,000 samples |
| Fields widest first (`Int` values, `Int32` fds, bytes) | no padding holes | 136 + 24 (name) + 68 + 256 = 484, rounded to 488 by the 8-byte struct alignment |
| `external_call["pread"]` straight to libc | a symbol resolved at link time, no `dlsym` per call | none per call |
| `NA = Int.MIN` instead of an `Optional` per metric | one `Int` slot per metric, no boxing | 17 slots, 136 bytes |
| Slots chosen once at open (labels read then) | the label scan (10 temps, 10 voltages) costs 20 file reads, so it is not repeated | `open` 150 to 210 µs, once |

## Not done, and why

- The sample time is the 17 system calls. Reading fewer files (a subset of slots) would be faster, but the
  daemon samples all of them, so no API for it.
- No `mmap`: sysfs attributes are not mappable.
- Peak RSS is the language runtime (11.6 MB); the library adds about 500 bytes. Python's 11.7 MB is
  the interpreter. There is no resident-memory win to claim, only the time and the absence of
  allocation.

## Oracle

`tools/oracle.py` reads the same tree with plain Python and prints every metric; the gate diffs
it with the Mojo runner on three trees: `tests/fixtures/sys` (copied from this machine by
`scripts/make-fixture.sh`: a 7900 XTX and an iGPU, three KFD nodes), `tests/fixtures/edge`
(hand-made by `scripts/make-edge.sh`: tie, numeric order, swapped labels, garbage values,
negative temperature, two hwmon dirs) and `tests/fixtures/empty`.
