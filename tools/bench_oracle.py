"""Same work as tests/bench.mojo in Python: open the best card's metric files once, os.pread them N times, parse.
argv[2] = "naive" re-opens, reads and closes every file on every sample instead (the usual daemon loop)."""
import os, re, sys, time

root, naive = sys.argv[1], len(sys.argv) > 2 and sys.argv[2] == "naive"
N = 100000


def parse(b, dpm):
    t = b.decode()
    if dpm:
        for line in t.splitlines():
            m = re.match(r"[^:]*:\s*(\d+).*\*", line)
            if m:
                return int(m.group(1))
        return None
    try:
        return int(t.strip())
    except ValueError:
        return None


t0 = time.perf_counter_ns()
best, bt = None, -1
for c in os.listdir(f"{root}/class/drm"):
    if re.fullmatch(r"card\d+", c):
        try:
            t = int(open(f"{root}/class/drm/{c}/device/mem_info_vram_total").read())
        except OSError:
            continue
        if t > bt:
            best, bt = c, t
d = f"{root}/class/drm/{best}/device"
h = f"{d}/hwmon/" + sorted(os.listdir(f"{d}/hwmon"))[0]
files = [f"{d}/mem_info_{k}" for k in ("vram_total", "vram_used", "vis_vram_total", "vis_vram_used", "gtt_total", "gtt_used")]
files += [f"{d}/gpu_busy_percent", f"{d}/mem_busy_percent", f"{d}/pp_dpm_sclk", f"{d}/pp_dpm_mclk"]
files += [f"{h}/temp{i}_input" for i in (1, 2, 3)] + [f"{h}/power1_average", f"{h}/power1_cap", f"{h}/fan1_input", f"{h}/in0_input"]
dpm = [i in (8, 9) for i in range(len(files))]
fds = [-1 if naive else os.open(f, os.O_RDONLY) for f in files]
t1 = time.perf_counter_ns()
total = 0
for _ in range(N):
    for i, f in enumerate(files):
        if naive:
            fd = os.open(f, os.O_RDONLY)
            b = os.pread(fd, 256, 0)
            os.close(fd)
        else:
            b = os.pread(fds[i], 256, 0)
        v = parse(b, dpm[i])
        if v is not None:
            total += v
t2 = time.perf_counter_ns()
print(f"open {(t1 - t0) // 1000} us; sample {(t2 - t1) // N} ns each; checksum {total}")
