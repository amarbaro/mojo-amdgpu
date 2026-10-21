"""Oracle: parse an amdgpu sysfs tree (default /sys) the way mojo-amdgpu must, print metrics per card.
Usage: oracle.py ROOT. Missing or non-numeric value prints "-". Units are the raw sysfs ones."""
import os, re, sys

KFD = ("gfx_target_version", "simd_count", "array_count", "cu_per_simd_array", "simd_per_cu",
       "wave_front_size", "lds_size_in_kb", "drm_render_minor", "device_id", "vendor_id")


def num(path):
    try:
        return int(open(path).read().strip())
    except (OSError, ValueError):
        return None


def text(path):
    try:
        return open(path).read().strip()
    except OSError:
        return None


def dpm(path):
    try:
        for line in open(path):
            m = re.match(r"[^:]*:\s*(\d+).*\*", line)
            if m:
                return int(m.group(1))
    except OSError:
        pass
    return None


def numeric_dirs(path, prefix):
    try:
        names = [n for n in os.listdir(path) if re.fullmatch(prefix + r"\d+", n)]
    except OSError:
        return []
    return sorted(names, key=lambda n: int(n[len(prefix):]))


def card_metrics(root, card):
    d = f"{root}/class/drm/{card}/device"
    m = {k: num(f"{d}/mem_info_{k}") for k in ("vram_total", "vram_used", "vis_vram_total", "vis_vram_used", "gtt_total", "gtt_used")}
    m["gpu_busy"] = num(f"{d}/gpu_busy_percent")
    m["mem_busy"] = num(f"{d}/mem_busy_percent")
    m["sclk_mhz"] = dpm(f"{d}/pp_dpm_sclk")
    m["mclk_mhz"] = dpm(f"{d}/pp_dpm_mclk")
    for k in ("temp_edge", "temp_junction", "temp_mem", "power_uw", "power_cap_uw", "fan_rpm", "vddgfx_mv"):
        m[k] = None
    hw = numeric_dirs(f"{d}/hwmon", "hwmon")
    if hw:
        h = f"{d}/hwmon/{hw[0]}"
        for i in range(1, 10):
            lab = text(f"{h}/temp{i}_label")
            if lab in ("edge", "junction", "mem") and m["temp_" + lab] is None:
                m["temp_" + lab] = num(f"{h}/temp{i}_input")
        for i in range(0, 10):
            if text(f"{h}/in{i}_label") == "vddgfx" and m["vddgfx_mv"] is None:
                m["vddgfx_mv"] = num(f"{h}/in{i}_input")
        p = num(f"{h}/power1_average")
        m["power_uw"] = p if p is not None else num(f"{h}/power1_input")
        m["power_cap_uw"] = num(f"{h}/power1_cap")
        m["fan_rpm"] = num(f"{h}/fan1_input")
    return m


def main(root):
    cards = [c for c in numeric_dirs(f"{root}/class/drm", "card") if os.path.exists(f"{root}/class/drm/{c}/device/mem_info_vram_total")]
    print("cards:" + "".join(" " + c for c in cards))
    best, bt = None, -1
    for c in cards:
        t = num(f"{root}/class/drm/{c}/device/mem_info_vram_total")
        if t is not None and t > bt:
            best, bt = c, t
    print("best:", best or "none")
    for c in cards:
        print(f"[{c}]")
        for k, v in card_metrics(root, c).items():
            print(k, "-" if v is None else v)
    nodes = f"{root}/class/kfd/kfd/topology/nodes"
    for n in sorted(os.listdir(nodes), key=int) if os.path.isdir(nodes) else []:
        props = {}
        for line in open(f"{nodes}/{n}/properties"):
            kv = line.split()
            if len(kv) == 2:
                props[kv[0]] = kv[1]
        if int(props.get("simd_count", "0")) > 0:
            print(f"kfd {n} " + " ".join(f"{k}={props.get(k, '-')}" for k in KFD))


main(sys.argv[1] if len(sys.argv) > 1 else "/sys")
