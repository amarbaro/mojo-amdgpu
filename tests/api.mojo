# Every behaviour docs/api.md states, on the fixtures (no GPU needed). Writes only under .work/.
from std.testing import assert_equal, assert_true, assert_raises
from amdgpu import Gpu, cards, best_card, kfd_nodes, NA
from amdgpu import VRAM_TOTAL, VRAM_USED, GPU_BUSY, MEM_BUSY, SCLK_MHZ, TEMP_EDGE, TEMP_JUNCTION, POWER_UW, POWER_CAP_UW, FAN_RPM

comptime SYS = "tests/fixtures/sys"
comptime EDGE = "tests/fixtures/edge"


def put(path: String, text: String) raises:
    with open(path, "w") as f:
        f.write(text)


def main() raises:
    # discovery: both fixture cards, the 7900 XTX (most VRAM) is the default
    assert_equal(len(cards(SYS)), 2)
    assert_equal(best_card(SYS), "card1")
    var g = Gpu(SYS)
    assert_equal(g.card, "card1")
    assert_equal(g.get(VRAM_TOTAL), 25753026560)
    assert_equal(g.get(VRAM_USED), 991805440)
    assert_equal(g.vram_free(), 25753026560 - 991805440)
    assert_equal(g.get(SCLK_MHZ), 43)  # the line marked '*'
    assert_equal(g.get(TEMP_JUNCTION), 47000)
    assert_equal(g.get(POWER_CAP_UW), 290000000)

    # an explicit card; the iGPU has no junction temperature, no cap, no mem_busy: NA, not 0
    var igpu = Gpu(SYS, "card0")
    assert_equal(igpu.get(TEMP_EDGE), 43000)
    assert_equal(igpu.get(TEMP_JUNCTION), NA)
    assert_equal(igpu.get(MEM_BUSY), NA)
    assert_equal(igpu.get(POWER_UW), 43576000)  # power1_input when power1_average is absent

    # numeric card order and first-wins tie on VRAM; "card0-DP-1" and a card without VRAM files are not cards
    var cs = cards(EDGE)
    assert_equal(len(cs), 3)
    assert_equal(cs[2], "card10")
    assert_equal(best_card(EDGE), "card2")
    var e = Gpu(EDGE, "card0")
    assert_equal(e.get(TEMP_EDGE), -5000)  # label decides the slot, sign kept
    assert_equal(e.get(TEMP_JUNCTION), 41000)
    assert_equal(e.get(GPU_BUSY), 100)  # no trailing newline
    assert_equal(e.get(MEM_BUSY), NA)  # N/A text
    assert_equal(e.get(SCLK_MHZ), 300)  # star on the first line
    assert_equal(Gpu(EDGE, "card10").get(FAN_RPM), 1500)
    assert_equal(Gpu(EDGE, "card2").get(TEMP_EDGE), NA)  # no hwmon at all

    # KFD: only nodes with SIMDs, numeric order
    var ns = kfd_nodes(EDGE)
    assert_equal(len(ns), 2)
    assert_equal(ns[1].node, 10)
    assert_equal(ns[0].gfx_target_version, 110000)
    assert_equal(ns[1].wave_front_size, NA)

    # refresh re-reads the same open files in place (what a daemon does every second); the gate copies EDGE to .work/api
    comptime W = ".work/api/class/drm/card0/device/"
    var r = Gpu(".work/api", "card0")
    assert_equal(r.get(VRAM_USED), 200)
    put(W + "mem_info_vram_used", "777\n")
    assert_equal(r.get(VRAM_USED), 200)  # not until refresh()
    r.refresh()
    assert_equal(r.get(VRAM_USED), 777)
    assert_equal(r.vram_free(), 223)
    put(W + "gpu_busy_percent", "oops")
    r.refresh()
    assert_equal(r.get(GPU_BUSY), NA)

    # no card: a clear error, and an empty list / name
    assert_equal(len(cards("tests/fixtures/empty")), 0)
    assert_equal(best_card("tests/fixtures/empty"), "")
    with assert_raises(contains="no amdgpu card"):
        _ = Gpu("tests/fixtures/empty")
    with assert_raises(contains="no amdgpu card"):
        _ = Gpu("does/not/exist")
