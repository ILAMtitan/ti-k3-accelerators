#!/usr/bin/env bash
set -Eeuo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
graph="$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-configure-imx708-graph"
preflight="$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-imx708-viss-preflight"
viss="$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-imx708-viss-smoke"
wave5="$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-imx708-wave5-720p60-smoke"
dcc="$root/scripts/build-imx708-default-dcc.sh"

for f in "$graph" "$preflight" "$viss" "$wave5" "$dcc"; do
  [[ -s "$f" ]] || { echo "Missing $f" >&2; exit 1; }
done

grep -Fq 'MODE=864p60' "$graph"
grep -Fq 'WIDTH=1536; HEIGHT=864; FPS=60; VBLANK=946' "$graph"
grep -Fq 'dcc_viss_${DCC_WIDTH}x${DCC_HEIGHT}.bin' "$graph"
grep -Fq 'IMX708_MODE:-864p60' "$preflight"
grep -Fq 'TI_K3_CAMERA_MODE" == 864p60' "$viss"
grep -Fq 'video/x-raw,format=NV12,width=1280,height=720,framerate=60/1' "$wave5"
grep -Fq 'tiovxmultiscaler target=0' "$wave5"
grep -Fq 'video_bitrate=${BITRATE}' "$wave5"
grep -Fq 'MODE=1536x864' "$dcc"
grep -Fq 'SENSOR_WIDTH=1536' "$dcc"
grep -Fq 'SENSOR_HEIGHT=864' "$dcc"

echo 'PASS: IMX708 720p60 R2 source contract'
