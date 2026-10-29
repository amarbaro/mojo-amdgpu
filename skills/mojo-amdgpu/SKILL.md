---
name: mojo-amdgpu
description: "Read AMD GPU VRAM, busy, power, temperature, clocks and KFD nodes from sysfs in Mojo with the mojo-amdgpu library, no ROCm. Use when Mojo code needs GPU telemetry or free VRAM."
---

# mojo-amdgpu

AMD GPU telemetry for Mojo 1.2 on Linux from sysfs, hwmon and KFD. Each value is checked
against a Python oracle on a copied sysfs tree.

## Install

`mojo run -I <repo>/src app.mojo`, or `mojo precompile <repo>/src/amdgpu -o amdgpu.mojoc`,
or copy `src/amdgpu/`.

## Use

```mojo
from amdgpu import Gpu, VRAM_USED, GPU_BUSY, NA

def main() raises:
    var g = Gpu()              # best card (most VRAM), files opened once
    g.refresh()                # call this each sample; get() is stale until then
    if g.get(GPU_BUSY) != NA:
        print(g.get(GPU_BUSY), "% busy,", g.vram_free() // 1048576, "MiB free")
```

## Rules

- **Make one `Gpu` and call `refresh()` on it.** Do not build a new `Gpu` per sample: that reopens every file.
- `get()` returns the value of the last `refresh()` (or of the constructor).
- Check for `NA` before using a metric a card may lack (the iGPU has no `MEM_BUSY`, no junction temperature, no power cap).
  `NA` is `Int.MIN`, not 0.
- Units are sysfs units: bytes, millidegrees C, microwatts, MHz, mV.
- `Gpu(root, card)`: pass a copied tree as `root` in tests; never point a test at a live `/sys` and compare values.
- `Gpu()` raises `no amdgpu card under /sys` when there is no card (a machine without the driver): handle it.
- The library only reads; it never writes to `/sys`.
- `kfd_nodes()` is a one-time read, not for the sample loop.

## Check a change to the library

`mojo build -I src tests/cases.mojo -o .work/cases` then `CASES=.work/cases scripts/check.sh`
must end with `PASS all`. To refresh the fixture on a new machine: `scripts/make-fixture.sh`.
