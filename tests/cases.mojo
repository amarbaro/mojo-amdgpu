# Case runner the gate drives: `cases ROOT` prints what tools/oracle.py prints for the same tree.
from std.sys import argv
from amdgpu import Gpu, KfdNode, cards, best_card, kfd_nodes, NA, NSLOT, SLOT_NAMES


def show(v: Int) -> String:
    return "-" if v == NA else String(v)


def main() raises:
    var root = String(argv()[1])
    var cs = cards(root)
    var line = String("cards:")
    for c in cs:
        line += " " + c
    print(line)
    var best = best_card(root)
    print("best:", best if best else "none")
    for c in cs:
        print("[" + c + "]")
        var g = Gpu(root, c)
        var names = String(SLOT_NAMES).split(" ")
        for i in range(NSLOT):
            print(names[i], show(g.get(i)))
    for k in kfd_nodes(root):
        print(
            "kfd", k.node, "gfx_target_version=" + show(k.gfx_target_version), "simd_count=" + show(k.simd_count),
            "array_count=" + show(k.array_count), "cu_per_simd_array=" + show(k.cu_per_simd_array),
            "simd_per_cu=" + show(k.simd_per_cu), "wave_front_size=" + show(k.wave_front_size),
            "lds_size_in_kb=" + show(k.lds_size_in_kb), "drm_render_minor=" + show(k.drm_render_minor),
            "device_id=" + show(k.device_id), "vendor_id=" + show(k.vendor_id),
        )
