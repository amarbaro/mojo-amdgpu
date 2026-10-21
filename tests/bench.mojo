# 100,000 samples of one card (what a 1 s daemon does for 28 h), files opened once. Same work as tools/bench_oracle.py.
from std.sys import argv, size_of
from std.time import perf_counter_ns
from amdgpu import Gpu, NSLOT, NA


def main() raises:
    comptime N = 100000
    var t0 = perf_counter_ns()
    var g = Gpu(String(argv()[1]))
    var t1 = perf_counter_ns()
    var sum = 0
    for _ in range(N):
        g.refresh()
        for i in range(NSLOT):
            if g.get(i) != NA:
                sum += g.get(i)
    var t2 = perf_counter_ns()
    print("Gpu is", size_of[Gpu](), "bytes; open", (t1 - t0) // 1000, "us; sample", (t2 - t1) // N, "ns each; checksum", sum)
