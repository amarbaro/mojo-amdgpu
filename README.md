# mojo-amdgpu

<!-- badges -->
[![ci](https://github.com/amarbaro/mojo-amdgpu/actions/workflows/ci.yml/badge.svg?branch=main)](https://github.com/amarbaro/mojo-amdgpu/actions/workflows/ci.yml) [![latest release](https://img.shields.io/github/v/release/amarbaro/mojo-amdgpu)](https://github.com/amarbaro/mojo-amdgpu/releases/latest) [![license](https://img.shields.io/github/license/amarbaro/mojo-amdgpu)](https://github.com/amarbaro/mojo-amdgpu/blob/main/LICENSE)
<!-- /badges -->

<!-- install -->
Install: `pixi add mojo-amdgpu` once published. For now: `git clone https://github.com/amarbaro/mojo-amdgpu`, then `mojo run -I mojo-amdgpu/src app.mojo`.

```mojo
from amdgpu import Gpu, VRAM_USED, GPU_BUSY, TEMP_JUNCTION, POWER_UW


def main() raises:
    # Gpu("/sys") is the default; the example reads the fixture so it runs anywhere.
    var g = Gpu("tests/fixtures/sys")  # opens the card with the most VRAM, files once
    for _ in range(3):  # a daemon would sleep 1 s between samples
        g.refresh()  # pread into one buffer, no allocation
        print(
            g.card, "vram used MiB", g.get(VRAM_USED) // 1048576, "free MiB", g.vram_free() // 1048576,
            "busy %", g.get(GPU_BUSY), "junction mC", g.get(TEMP_JUNCTION), "power uW", g.get(POWER_UW),
        )
```

| | per sample | peak RSS |
|---|---|---|
| Mojo, `Gpu.refresh()` | 8.0 to 8.6 µs | 11.6 to 11.7 MB |
<!-- /install -->


AMD GPU telemetry for Mojo from sysfs, hwmon and KFD, no ROCm and no `rocm-smi` needed. Every
value is checked against a Python oracle on a copy of a real 7900 XTX + iGPU sysfs tree, and a
sample (17 metrics) costs 8 µs, about 2.2× faster than Python with `pread` and about 7× faster than Python
that re-opens each file, with no allocation per sample.

```mojo
from amdgpu import Gpu, VRAM_USED, TEMP_JUNCTION

def main() raises:
    var g = Gpu()  # the card with the most VRAM under /sys; files opened once
    while True:
        g.refresh()  # pread into one buffer, parse in place
        print(g.get(VRAM_USED), g.vram_free(), g.get(TEMP_JUNCTION))
        # sleep 1 s
```

## Install

Requires Mojo 1.2 on Linux with the `amdgpu` driver. Nothing to link.

| Way | Command |
|---|---|
| Source path | `mojo run -I path/to/mojo-amdgpu/src app.mojo` |
| Precompiled | `mojo precompile src/amdgpu -o amdgpu.mojoc`, put it next to your code |
| Vendor | copy `src/amdgpu/` into your project |

## What you get

- `Gpu(root="/sys", card="")`: one card, 17 metrics (VRAM, visible VRAM, GTT, busy, memory busy,
  sclk, mclk, edge, junction and memory temperature, power, power cap, fan, vddgfx). `refresh()`
  and `get(slot)`. A metric the card does not have reads `NA`, never 0.
- `cards()`, `best_card()`: DRM cards in numeric order, and the one with the most VRAM
  (as `vram-free` does).
- `kfd_nodes()`: the KFD topology nodes that have SIMDs (gfx target, SIMD count, wave size,
  LDS, render minor, device id).
- The root path is a parameter, so tests and CI run on a copied tree, never on the GPU.

The API is in [docs/api.md](docs/api.md), the memory design in [docs/design.md](docs/design.md).

## Performance

`tests/bench.mojo` against `tools/bench_oracle.py`: 100,000 samples of the best card's 17 files on the
fixture (the page-cache cost of `pread`; real sysfs adds the driver's own read time to both sides).
Three runs each.

| | per sample | peak RSS |
|---|---|---|
| Python, files opened once, `os.pread` | 17.7 to 18.1 µs | 11.7 to 11.9 MB |
| Python, open + read + close each time | 57.9 to 60.0 µs | 11.9 MB |
| Mojo, `Gpu.refresh()` | 8.0 to 8.6 µs | 11.6 to 11.7 MB |

The sample time is mostly the 17 `pread` system calls (about 470 ns each). Peak RSS is the runtime
floor of both: it does not move over 100,000 samples, and a `Gpu` is 488 bytes. Mojo does not save
resident memory here, it saves time and does not allocate.

## Limits

- Linux only. Values are the raw sysfs units (bytes, millidegrees, microwatts, MHz, mV).
- One hwmon directory per card (the lowest number). Temperatures are found by label
  (`edge`, `junction`, `mem`); other labels are ignored.
- Digits only: `int()` forms Python accepts such as `1_0` read as `NA`.
- KFD data is read once when you call `kfd_nodes()`, it is not hot-path.
- Not covered: fan control, clock or power writes (the library never writes to `/sys`),
  per-process VRAM.

## Check

`CASES=.work/cases scripts/check.sh` (build the runner first: `mojo build -I src tests/cases.mojo -o .work/cases`)
ends with `PASS all`. `scripts/make-fixture.sh` re-copies the sysfs files of the machine.
