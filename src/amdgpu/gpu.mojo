"""AMD GPU telemetry from sysfs/hwmon/KFD, no ROCm. Files are opened once; `refresh()` re-reads them
with pread into one fixed buffer and parses in place: no allocation, no path lookup per sample."""
from std.ffi import external_call, c_ssize_t
from std.os import listdir
from std.builtin.sort import sort

comptime NA = Int.MIN  # absent file or non-numeric content
comptime O_CLOEXEC = 524288

comptime VRAM_TOTAL = 0
comptime VRAM_USED = 1
comptime VIS_VRAM_TOTAL = 2
comptime VIS_VRAM_USED = 3
comptime GTT_TOTAL = 4
comptime GTT_USED = 5
comptime GPU_BUSY = 6
comptime MEM_BUSY = 7
comptime SCLK_MHZ = 8  # the DPM level marked '*'
comptime MCLK_MHZ = 9
comptime TEMP_EDGE = 10  # millidegrees C
comptime TEMP_JUNCTION = 11
comptime TEMP_MEM = 12
comptime POWER_UW = 13  # power1_average, else power1_input
comptime POWER_CAP_UW = 14
comptime FAN_RPM = 15
comptime VDDGFX_MV = 16
comptime NSLOT = 17
comptime SLOT_NAMES = "vram_total vram_used vis_vram_total vis_vram_used gtt_total gtt_used gpu_busy mem_busy sclk_mhz mclk_mhz temp_edge temp_junction temp_mem power_uw power_cap_uw fan_rpm vddgfx_mv"  # space-separated, slot order


def _open(path: String) -> Int32:
    var p = path.copy()
    return external_call["open64", Int32](p.as_c_string_span().ptr(), Int32(O_CLOEXEC))


def _is_ws(c: UInt8) -> Bool:
    return c == 32 or (c >= 9 and c <= 13)


def _int(s: Span[UInt8, _]) -> Int:
    """Trimmed decimal with optional sign; anything else is NA."""
    var i = 0
    var n = len(s)
    while i < n and _is_ws(s[i]):
        i += 1
    var neg = i < n and s[i] == 45
    if i < n and (s[i] == 45 or s[i] == 43):
        i += 1
    var v = 0
    var digits = 0
    while i < n and s[i] >= 48 and s[i] <= 57:
        v = v * 10 + Int(s[i] - 48)
        digits += 1
        i += 1
    while i < n and _is_ws(s[i]):
        i += 1
    return (-v if neg else v) if digits > 0 and i == n else NA


def _dpm(s: Span[UInt8, _]) -> Int:
    """pp_dpm_* lines look like `1: 600Mhz *`; return the number of the line that carries the star."""
    var n = len(s)
    var i = 0
    while i < n:
        var j = i
        var star = False
        var colon = -1
        while j < n and s[j] != 10:
            if s[j] == 42:
                star = True
            elif s[j] == 58 and colon < 0:
                colon = j
            j += 1
        if star and colon >= 0:
            var k = colon + 1
            while k < j and _is_ws(s[k]):
                k += 1
            var v = 0
            var digits = 0
            while k < j and s[k] >= 48 and s[k] <= 57:
                v = v * 10 + Int(s[k] - 48)
                digits += 1
                k += 1
            if digits > 0:
                return v
        i = j + 1
    return NA


def _slurp(path: String, mut buf: Span[UInt8, _]) -> Int:
    """Cold-path read of a whole small file into `buf`; -1 when it cannot be opened."""
    var fd = _open(path)
    if fd < 0:
        return -1
    var n = Int(external_call["pread", c_ssize_t](fd, buf.unsafe_ptr(), len(buf), Int64(0)))
    _ = external_call["close", Int32](fd)
    return n


def _numdirs(path: String, prefix: String) raises -> List[Int]:
    """Numbers N of the entries named `<prefix>N` in `path`, ascending (card2 before card10)."""
    var out = List[Int]()
    try:
        for name in listdir(path):
            if name.startswith(prefix) and name.byte_length() > prefix.byte_length():
                var rest = name[byte = prefix.byte_length() :]
                var n = _int(rest.as_bytes())
                if n != NA and n >= 0 and String(n) == rest:
                    out.append(n)
    except:
        pass
    sort(out)
    return out^


def _first_int(path: String) -> Int:
    var b = Array[UInt8, 64](fill=0)
    var sp = Span[UInt8](b)
    var n = _slurp(path, sp)
    return _int(sp[:n]) if n > 0 else NA


def _text(path: String) -> String:
    var b = Array[UInt8, 64](fill=0)
    var sp = Span[UInt8](b)
    var n = _slurp(path, sp)
    if n <= 0:
        return String()
    return String(StringSlice(unsafe_from_utf8=sp[:n]).strip())


def cards(root: String = "/sys") raises -> List[String]:
    """Names (`card0`, `card1`, ...) of the DRM cards that expose VRAM files, in numeric order."""
    var out = List[String]()
    for n in _numdirs(root + "/class/drm", "card"):
        if _first_int(root + "/class/drm/card" + String(n) + "/device/mem_info_vram_total") != NA:
            out.append("card" + String(n))
    return out^


def best_card(root: String = "/sys") raises -> String:
    """The card with the most VRAM (first wins a tie); empty when there is none."""
    var best = String()
    var top = -1
    for c in cards(root):
        var t = _first_int(root + "/class/drm/" + c + "/device/mem_info_vram_total")
        if t > top:
            top = t
            best = c.copy()
    return best^


struct Gpu(Movable):
    var vals: Array[Int, NSLOT]
    var card: String
    var fds: Array[Int32, NSLOT]
    var buf: Array[UInt8, 256]

    def __init__(out self, root: String = "/sys", card: String = "") raises:
        """Open one card (default: the one with the most VRAM) and every metric file it has."""
        self.card = card.copy() if card else best_card(root)
        if not self.card:
            raise Error("no amdgpu card under " + root)
        self.vals = Array[Int, NSLOT](fill=NA)
        self.fds = Array[Int32, NSLOT](fill=-1)
        self.buf = Array[UInt8, 256](fill=0)
        var d = root + "/class/drm/" + self.card + "/device"
        var names = String(SLOT_NAMES).split(" ")
        for i in range(6):
            self.fds[i] = _open(d + "/mem_info_" + String(names[i]))
        self.fds[GPU_BUSY] = _open(d + "/gpu_busy_percent")
        self.fds[MEM_BUSY] = _open(d + "/mem_busy_percent")
        self.fds[SCLK_MHZ] = _open(d + "/pp_dpm_sclk")
        self.fds[MCLK_MHZ] = _open(d + "/pp_dpm_mclk")
        var hw = _numdirs(d + "/hwmon", "hwmon")
        if len(hw) > 0:
            var h = d + "/hwmon/hwmon" + String(hw[0])
            for i in range(1, 10):
                var lab = _text(h + "/temp" + String(i) + "_label")
                var slot = TEMP_EDGE if lab == "edge" else (TEMP_JUNCTION if lab == "junction" else (TEMP_MEM if lab == "mem" else -1))
                if slot >= 0 and self.fds[slot] < 0:
                    self.fds[slot] = _open(h + "/temp" + String(i) + "_input")
            for i in range(10):
                if self.fds[VDDGFX_MV] < 0 and _text(h + "/in" + String(i) + "_label") == "vddgfx":
                    self.fds[VDDGFX_MV] = _open(h + "/in" + String(i) + "_input")
            self.fds[POWER_UW] = _open(h + "/power1_average")
            if self.fds[POWER_UW] < 0 or _first_int(h + "/power1_average") == NA:
                _ = external_call["close", Int32](self.fds[POWER_UW])
                self.fds[POWER_UW] = _open(h + "/power1_input")
            self.fds[POWER_CAP_UW] = _open(h + "/power1_cap")
            self.fds[FAN_RPM] = _open(h + "/fan1_input")
        self.refresh()

    def __deinit__(deinit self):
        for i in range(NSLOT):
            if self.fds[i] >= 0:
                _ = external_call["close", Int32](self.fds[i])

    def refresh(mut self):
        """Re-read every open file: one pread each into the shared buffer, parsed in place."""
        var p = self.buf.unsafe_ptr()
        for i in range(NSLOT):
            if self.fds[i] < 0:
                continue
            var n = Int(external_call["pread", c_ssize_t](self.fds[i], p, 256, Int64(0)))
            var s = Span[UInt8](unsafe_ptr=p, length=max(n, 0))
            self.vals[i] = _dpm(s) if (i == SCLK_MHZ or i == MCLK_MHZ) else _int(s)

    def get(self, slot: Int) -> Int:
        return self.vals[slot]

    def vram_free(self) -> Int:
        return self.vals[VRAM_TOTAL] - self.vals[VRAM_USED]


@fieldwise_init
struct KfdNode(Copyable, Movable):
    """A KFD topology node that has SIMDs (a GPU, not the CPU node). NA when a property is absent."""

    var node: Int
    var gfx_target_version: Int
    var simd_count: Int
    var array_count: Int
    var cu_per_simd_array: Int
    var simd_per_cu: Int
    var wave_front_size: Int
    var lds_size_in_kb: Int
    var drm_render_minor: Int
    var device_id: Int
    var vendor_id: Int


def _prop(text: StringSlice, key: String) -> Int:
    for line in text.split("\n"):
        var kv = line.split(" ")
        if len(kv) == 2 and kv[0] == key:
            return _int(kv[1].as_bytes())
    return NA


def kfd_nodes(root: String = "/sys") raises -> List[KfdNode]:
    var out = List[KfdNode]()
    var dir = root + "/class/kfd/kfd/topology/nodes"
    var b = Array[UInt8, 4096](fill=0)
    var sp = Span[UInt8](b)
    for n in _numdirs(dir, ""):
        var len = _slurp(dir + "/" + String(n) + "/properties", sp)
        if len <= 0:
            continue
        var t = StringSlice(unsafe_from_utf8=sp[:len])
        var simd = _prop(t, "simd_count")
        if simd != NA and simd > 0:
            out.append(KfdNode(
                n, _prop(t, "gfx_target_version"), simd, _prop(t, "array_count"), _prop(t, "cu_per_simd_array"),
                _prop(t, "simd_per_cu"), _prop(t, "wave_front_size"), _prop(t, "lds_size_in_kb"),
                _prop(t, "drm_render_minor"), _prop(t, "device_id"), _prop(t, "vendor_id"),
            ))
    return out^
