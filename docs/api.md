# API

```mojo
from amdgpu import Gpu, KfdNode, cards, best_card, kfd_nodes, NA
from amdgpu import VRAM_USED, GPU_BUSY, TEMP_JUNCTION   # slot numbers, see below
```

Every function takes `root` (default `"/sys"`): the directory that contains `class/drm` and
`class/kfd`. All values are the raw sysfs numbers. The library never writes to `/sys`.

## Discovery

| Call | Does |
|---|---|
| `cards(root) -> List[String]` | names (`card0`, `card1`) of the DRM entries that have `device/mem_info_vram_total`, in numeric order (`card2` before `card10`); `card0-DP-1` is not a card |
| `best_card(root) -> String` | the card with the most VRAM, the first of a tie; `""` when there is none |
| `kfd_nodes(root) -> List[KfdNode]` | the nodes of `class/kfd/kfd/topology/nodes` whose `simd_count` is above 0, in numeric order |

`KfdNode` fields: `node`, `gfx_target_version`, `simd_count`, `array_count`, `cu_per_simd_array`,
`simd_per_cu`, `wave_front_size`, `lds_size_in_kb`, `drm_render_minor`, `device_id`, `vendor_id`
(`NA` when the property is missing).

## `Gpu`

| Call | Does |
|---|---|
| `Gpu(root="/sys", card="")` | open `card` (default: `best_card`) and every metric file it has; reads once. Raises `no amdgpu card under <root>` when there is no card |
| `g.card` | the card name |
| `g.refresh()` | re-read every open file: one `pread` each, into one shared 256-byte buffer, parsed in place. Never raises, never allocates |
| `g.get(slot) -> Int` | the value from the last read; `NA` (`Int.MIN`) when the file is absent, unreadable or not a number |
| `g.vram_free() -> Int` | `VRAM_TOTAL - VRAM_USED` |

Files are closed when the `Gpu` is destroyed. A `Gpu` does not copy.

## Slots

| Slot | Source | Unit |
|---|---|---|
| `VRAM_TOTAL`, `VRAM_USED` | `mem_info_vram_*` | bytes |
| `VIS_VRAM_TOTAL`, `VIS_VRAM_USED` | `mem_info_vis_vram_*` | bytes |
| `GTT_TOTAL`, `GTT_USED` | `mem_info_gtt_*` | bytes |
| `GPU_BUSY`, `MEM_BUSY` | `gpu_busy_percent`, `mem_busy_percent` (the iGPU has no memory busy) | % |
| `SCLK_MHZ`, `MCLK_MHZ` | the line marked `*` in `pp_dpm_sclk`, `pp_dpm_mclk` | MHz |
| `TEMP_EDGE`, `TEMP_JUNCTION`, `TEMP_MEM` | the hwmon `tempN_input` whose `tempN_label` is `edge`, `junction`, `mem` | millidegrees C |
| `POWER_UW` | `power1_average`, else `power1_input` | microwatts |
| `POWER_CAP_UW` | `power1_cap` | microwatts |
| `FAN_RPM` | `fan1_input` | rpm |
| `VDDGFX_MV` | the `inN_input` whose `inN_label` is `vddgfx` | mV |

`SLOT_NAMES` is the same list as one space-separated string, in slot order; `NSLOT` is 17.

## Parsing rules

Asserted in `tests/api.mojo`, compared with Python in `scripts/check.sh`:

- A value is a decimal integer with optional sign and surrounding whitespace (no trailing newline needed).
  `N/A`, empty or mixed text reads `NA`.
- A card without hwmon, or without a file, reads `NA` for that metric (not 0).
- The hwmon directory is the lowest-numbered one (`hwmon9` before `hwmon10`); the label, not the
  index, decides the temperature slot.
- `refresh()` sees a changed file; `get()` does not until then.
