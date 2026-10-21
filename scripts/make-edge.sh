#!/usr/bin/env bash
# Hand-made edge fixture tests/fixtures/edge: tie on VRAM, numeric card order (card2 < card10),
# a card without VRAM files, two hwmon dirs (hwmon9 < hwmon10), swapped temp labels, negative temp,
# garbage / padded / newline-less values, star on the first DPM line, power1_input only.
set -euo pipefail
cd "$(dirname "$0")/.."
r=tests/fixtures/edge; rm -rf "$r"
w() { mkdir -p "$(dirname "$r/$1")"; printf '%s' "$2" > "$r/$1"; }
d=class/drm
w $d/card0/device/mem_info_vram_total $'1000\n'; w $d/card0/device/mem_info_vram_used $'200\n'
w $d/card0/device/gpu_busy_percent '100'; w $d/card0/device/mem_busy_percent $'N/A\n'
w $d/card0/device/pp_dpm_sclk $'0: 300Mhz *\n1: 900Mhz \n'; w $d/card0/device/pp_dpm_mclk $'0: 96Mhz\n1: 1249Mhz\n'
w $d/card0/device/mem_info_gtt_used $'  12 \n'
h=$d/card0/device/hwmon
w $h/hwmon9/temp1_input $'41000\n'; w $h/hwmon9/temp1_label $'junction\n'
w $h/hwmon9/temp2_input $'-5000\n'; w $h/hwmon9/temp2_label $'edge\n'
w $h/hwmon9/power1_input $'43576000\n'; w $h/hwmon9/in0_input $'960\n'; w $h/hwmon9/in0_label $'vddgfx\n'
w $h/hwmon10/temp1_input $'99000\n'; w $h/hwmon10/temp1_label $'edge\n'
w $d/card1/device/uevent $'DRIVER=x\n'
w $d/card2/device/mem_info_vram_total $'9000\n'; w $d/card2/device/mem_info_vram_used $'0\n'
w $d/card10/device/mem_info_vram_total $'9000\n'; w $d/card10/device/mem_info_vram_used $'9000\n'
w $d/card10/device/hwmon/hwmon3/fan1_input $'1500\n'
mkdir -p "$r/$d/card0-DP-1/device"; w $d/card0-DP-1/device/mem_info_vram_total $'99999\n'
k=class/kfd/kfd/topology/nodes
w $k/0/properties $'cpu_cores_count 16\nsimd_count 0\n'
w $k/1/properties $'simd_count 192\ngfx_target_version 110000\nwave_front_size 32\nlds_size_in_kb 64\nvendor_id 4098\n'
w $k/3/properties $'simd_count 0\n'
w $k/10/properties $'simd_count 4\narray_count 1\nvendor_id 4098'
mkdir -p tests/fixtures/empty; : > tests/fixtures/empty/.gitkeep
