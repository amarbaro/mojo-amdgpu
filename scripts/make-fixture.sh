#!/usr/bin/env bash
# Copy (read-only cat) the amdgpu sysfs files into tests/fixtures/sys, keeping paths. Never writes to /sys.
set -euo pipefail
cd "$(dirname "$0")/.."
out=tests/fixtures/sys
rm -rf "$out"
cp1() { # $1 = real file; keep its path under $out, resolving the card symlink
  local rel=${1#/sys/}
  mkdir -p "$out/$(dirname "$rel")"
  cat "$1" > "$out/$rel"
}
for card in /sys/class/drm/card[0-9]*; do
  [[ $card =~ card[0-9]+$ ]] || continue
  d=$card/device
  for f in "$d"/mem_info_* "$d"/gpu_busy_percent "$d"/mem_busy_percent "$d"/pp_dpm_sclk "$d"/pp_dpm_mclk \
           "$d"/hwmon/hwmon*/*_input "$d"/hwmon/hwmon*/*_label "$d"/hwmon/hwmon*/power1_cap "$d"/hwmon/hwmon*/power1_average "$d"/hwmon/hwmon*/name; do
    [ -f "$f" ] && cp1 "$f" || true
  done
done
for f in /sys/class/kfd/kfd/topology/nodes/*/properties; do cp1 "$f"; done
echo "fixture: $(find "$out" -type f | wc -l) files, $(du -sk "$out" | cut -f1) KiB"
