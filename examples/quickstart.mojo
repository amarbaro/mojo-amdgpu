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
