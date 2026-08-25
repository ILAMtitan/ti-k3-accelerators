#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
patch="$root/armbian/userpatches/kernel/archive/k3-beagle-6.12/0003-arm64-dts-ti-build-BeagleY-AI-TI-K3-camera-overlays.patch"
base="$root/armbian/userpatches/kernel/archive/k3-beagle-6.12/dt"
helper="$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-configure-imx415-graph"
preflight="$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-imx415-viss-preflight"
smoke="$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-imx415-viss-smoke"
wave5="$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-imx415-wave5-smoke"
selector="$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-select-imx415-overlay"
live="$root/scripts/install-imx415-live.sh"
dcc="$root/scripts/build-imx415-default-dcc.sh"

for f in "$base/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtso" \
         "$base/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-1a.dtso" \
         "$helper" "$preflight" "$smoke" "$wave5" "$selector" "$live" "$dcc"; do
  [[ -s "$f" ]]
done

grep -Fq 'link-frequencies = /bits/ 64 <720000000>;' "$base/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtso"
grep -Fq 'reg = <0x37>;' "$base/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtso"
grep -Fq 'reg = <0x1a>;' "$base/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-1a.dtso"
grep -Fq 'b0569-imx415-37.dtbo' "$patch"
grep -Fq 'b0569-imx415-1a.dtbo' "$patch"
grep -Fq 'BAYER_MBUS=SGBRG10_1X10' "$helper"
grep -Fq 'BAYER_V4L2=GB10' "$helper"
grep -Fq 'PIXEL_RATE" != 304615385' "$helper"
grep -Fq 'gbrg10le' "$preflight"
grep -Fq 'sensor-name=SENSOR_SONY_IMX219_RPI' "$smoke"
grep -Fq 'tiovxmultiscaler target=0' "$wave5"
grep -Fq 'video_bitrate=${BITRATE}' "$wave5"
grep -Fq 'v6.12.49-ti-arm64-r56' "$live"
grep -Fq '/extra/arducam/imx415.ko' "$live"
grep -Fq 'ti-k3-select-imx415-overlay --address 0x37' "$live"
grep -Fq 'COLOR_PATTERN 2' "$dcc"
grep -Fq 'BLACK_PRE 50' "$dcc"

echo 'PASS: IMX415 R0 accelerator source contract'
