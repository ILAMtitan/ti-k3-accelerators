#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

root=$(cd "$(dirname "$0")/.." && pwd)
DCC_DIR=
NO_DCC=no
GST_OVERRIDE=/opt/ti-k3/gstreamer-overrides/gstreamer-1.0/libgstvideo4linux2.so
GST_ENV=/etc/ti-k3/gstreamer.env

usage() {
  cat >&2 <<USAGE
Usage: $0 --dcc-dir DIR
       $0 --no-dcc

Install the IMX708 720p60 final-qualified graph/preflight/smoke helpers onto
an existing qualified BeagleY-AI TI-K3 runtime.

--dcc-dir DIR  copy dcc_viss_1536x864.bin and dcc_2a_1536x864.bin from DIR
--no-dcc       leave existing /opt/imaging/imx708/linear DCC files untouched

The final checkpoint REQUIRES the negotiated-resolution GStreamer V4L2 CMA
override to already be installed and selected. If it is not installed, run:

  $root/scripts/build-install-gstreamer-v4l2-cma-override.sh

This script does NOT change uEnv.txt, device-tree overlays, the TI runtime,
remoteproc firmware, the EdgeAI memory map, or reboot the board.
USAGE
  exit 2
}

while (($#)); do
  case "$1" in
    --dcc-dir) DCC_DIR=${2:?missing directory}; shift 2 ;;
    --no-dcc) NO_DCC=yes; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

if [[ "$NO_DCC" == no && -z "$DCC_DIR" ]]; then
  usage
fi
if [[ "$NO_DCC" == yes && -n "$DCC_DIR" ]]; then
  echo 'Use either --dcc-dir or --no-dcc, not both.' >&2
  exit 2
fi

src="$root/armbian/userpatches/overlay/usr/local/sbin"
helpers=(
  ti-k3-configure-imx708-graph
  ti-k3-imx708-viss-preflight
  ti-k3-imx708-viss-smoke
  ti-k3-imx708-wave5-720p60-smoke
)

for h in "${helpers[@]}"; do
  [[ -s "$src/$h" ]] || { echo "Missing source helper: $src/$h" >&2; exit 1; }
done

if [[ "$NO_DCC" == no ]]; then
  DCC_DIR=$(readlink -f "$DCC_DIR")
  [[ -s "$DCC_DIR/dcc_viss_1536x864.bin" ]] || { echo "Missing $DCC_DIR/dcc_viss_1536x864.bin" >&2; exit 1; }
  [[ -s "$DCC_DIR/dcc_2a_1536x864.bin" ]] || { echo "Missing $DCC_DIR/dcc_2a_1536x864.bin" >&2; exit 1; }
fi

[[ -r "$GST_ENV" ]] || { echo "Missing $GST_ENV" >&2; exit 1; }
[[ -s "$GST_OVERRIDE" ]] || {
  echo "Missing qualified GStreamer V4L2 override: $GST_OVERRIDE" >&2
  echo "Run: $root/scripts/build-install-gstreamer-v4l2-cma-override.sh" >&2
  exit 1
}

unset GST_PLUGIN_PATH GST_PLUGIN_PATH_1_0 GST_REGISTRY || true
set -a
# shellcheck source=/dev/null
source "$GST_ENV"
set +a
export GST_REGISTRY=/tmp/gst-registry-imx708-live-installer.bin
rm -f "$GST_REGISTRY"

filename=$(gst-inspect-1.0 v4l2h264enc 2>/dev/null |
  awk -F'[[:space:]]+' '/^[[:space:]]*Filename[[:space:]]/{print $3; exit}')
[[ "$filename" == "$GST_OVERRIDE" ]] || {
  echo "GStreamer override is not selected; got: $filename" >&2
  exit 1
}

install -d -m 0755 /usr/local/sbin
for h in "${helpers[@]}"; do
  install -m 0755 "$src/$h" "/usr/local/sbin/$h"
done

if [[ "$NO_DCC" == no ]]; then
  install -d -m 0755 /opt/imaging/imx708/linear
  install -m 0644 "$DCC_DIR/dcc_viss_1536x864.bin" /opt/imaging/imx708/linear/dcc_viss_1536x864.bin
  install -m 0644 "$DCC_DIR/dcc_2a_1536x864.bin" /opt/imaging/imx708/linear/dcc_2a_1536x864.bin
fi

for h in "${helpers[@]}"; do
  [[ -x "/usr/local/sbin/$h" ]] || { echo "Installed helper is not executable: $h" >&2; exit 1; }
done
for f in \
  /opt/imaging/imx708/linear/dcc_viss_1536x864.bin \
  /opt/imaging/imx708/linear/dcc_2a_1536x864.bin; do
  [[ -s "$f" ]] || { echo "Required R2 DCC file is missing: $f" >&2; exit 1; }
done

cat <<EOF
IMX708 720p60 final-qualified live files installed.

No reboot is required for this change.
Do not start OpenHD yet. Qualify in this order:

  ti-k3-configure-imx708-graph --mode 864p60 --verify-stream --verify-frames 600
  FRAMES=600 ti-k3-imx708-viss-smoke
  FRAMES=600 ti-k3-imx708-wave5-720p60-smoke

The Wave5 smoke must complete without a 33,554,432-byte / 8192-page CMA
allocation failure before proceeding to OpenHD RF qualification.
EOF
