#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }
root=$(cd "$(dirname "$0")/.." && pwd)
overlay="$root/armbian/userpatches/overlay"
start=no
case "${1:-}" in
  "") ;;
  --start) start=yes ;;
  -h|--help)
    echo "Usage: sudo $0 [--start]"
    exit 0
    ;;
  *) echo "Usage: sudo $0 [--start]" >&2; exit 2 ;;
esac

camera_scripts=(
  ti-k3-camera-select
  ti-k3-camera-setup
  ti-k3-camera-prepare
  ti-k3-find-camera-devices
  ti-k3-configure-imx219-graph
  ti-k3-configure-imx708-graph
  ti-k3-configure-imx415-graph
)
for s in "${camera_scripts[@]}"; do
  [[ -s "$overlay/usr/local/sbin/$s" ]] || {
    echo "Missing R4 camera script: $overlay/usr/local/sbin/$s" >&2
    exit 1
  }
done
for u in ti-k3-camera-prepare.service ti-k3-imx219-prepare.service; do
  [[ -s "$overlay/etc/systemd/system/$u" ]] || {
    echo "Missing R4 camera unit: $overlay/etc/systemd/system/$u" >&2
    exit 1
  }
done

install -d -m 0755 /usr/local/sbin /etc/systemd/system /etc/ti-k3
for s in "${camera_scripts[@]}"; do
  install -m 0755 "$overlay/usr/local/sbin/$s" "/usr/local/sbin/$s"
done
for u in ti-k3-camera-prepare.service ti-k3-imx219-prepare.service; do
  install -m 0644 "$overlay/etc/systemd/system/$u" "/etc/systemd/system/$u"
done

systemctl daemon-reload

echo 'Installed TI K3 R4 unified camera selector and all three graph helpers.'
ti-k3-camera-select status || true

if [[ "$start" == yes ]]; then
  systemctl stop ti-k3-imx219-prepare.service ti-k3-camera-prepare.service 2>/dev/null || true
  systemctl start ti-k3-camera-prepare.service
  systemctl --no-pager --full status ti-k3-camera-prepare.service || true
  echo
  cat /run/ti-k3/camera.env
else
  echo 'Camera service was not started. Use:'
  echo '  systemctl start ti-k3-camera-prepare.service'
fi
