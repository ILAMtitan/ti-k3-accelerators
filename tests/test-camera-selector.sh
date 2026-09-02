#!/usr/bin/env bash
set -Eeuo pipefail

selector=${1:-./armbian/userpatches/overlay/usr/local/sbin/ti-k3-camera-select}
[[ -x "$selector" ]] || { echo "Selector is not executable: $selector" >&2; exit 1; }

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/etc" "$tmp/boot/dtb/ti" "$tmp/run"
cat > "$tmp/boot/uEnv.txt" <<'EOF_UENV'
verbosity=1
name_overlays=ti/unrelated-a.dtbo ti/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtbo ti/unrelated-b.dtbo
rootdev=UUID=test
EOF_UENV
for f in \
  k3-am67a-beagley-ai-csi1-imx219.dtbo \
  k3-am67a-beagley-ai-csi0-arducam-b0310.dtbo \
  k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtbo; do
  printf x > "$tmp/boot/dtb/ti/$f"
done

run_selector() {
  TI_K3_CAMERA_CONFIG_FILE="$tmp/etc/camera.conf" \
  TI_K3_CAMERA_UENV_FILE="$tmp/boot/uEnv.txt" \
  TI_K3_DTB_ROOT="$tmp/boot/dtb" \
  TI_K3_CAMERA_RUN_ENV="$tmp/run/camera.env" \
  TI_K3_CAMERA_ALLOW_UNPRIVILEGED=yes \
    "$selector" "$@"
}

run_selector imx708 >/tmp/ti-k3-camera-selector-test.out

grep -Fq 'ti/unrelated-a.dtbo' "$tmp/boot/uEnv.txt"
grep -Fq 'ti/unrelated-b.dtbo' "$tmp/boot/uEnv.txt"
grep -Fq 'ti/k3-am67a-beagley-ai-csi0-arducam-b0310.dtbo' "$tmp/boot/uEnv.txt"
! grep -Fq 'b0569-imx415' "$tmp/boot/uEnv.txt"
grep -Fxq 'TI_K3_CAMERA_SELECTED=imx708' "$tmp/etc/camera.conf"
grep -Fxq 'TI_K3_OPENHD_CAMERA_TYPE=151' "$tmp/etc/camera.conf"

status=$(run_selector status)
grep -Fq 'configured_sensor=imx708' <<<"$status"
grep -Fq 'state=boot-configured' <<<"$status"

run_selector imx219 >/tmp/ti-k3-camera-selector-test.out
grep -Fq 'ti/k3-am67a-beagley-ai-csi1-imx219.dtbo' "$tmp/boot/uEnv.txt"
! grep -Fq 'arducam-b0310' "$tmp/boot/uEnv.txt"
grep -Fxq 'TI_K3_OPENHD_CAMERA_TYPE=150' "$tmp/etc/camera.conf"

printf 'PASS: unified camera selector preserves unrelated overlays and maps all state atomically\n'
