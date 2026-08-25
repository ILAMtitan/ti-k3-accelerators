#!/usr/bin/env bash
set -Eeuo pipefail

[[ $(id -u) -eq 0 ]] || { echo 'Run as root' >&2; exit 1; }

root=$(cd "$(dirname "$0")/.." && pwd)
KVER=$(uname -r)
KBUILD=/lib/modules/$KVER/build
WORK=${WORK:-/var/tmp/ti-k3-imx415-live-$KVER}
DRIVER_REF=v6.12.49-ti-arm64-r56
DRIVER_URL=${IMX415_SOURCE_URL:-https://raw.githubusercontent.com/beagleboard/linux/${DRIVER_REF}/drivers/media/i2c/imx415.c}
DT_DIR="$root/armbian/userpatches/kernel/archive/k3-beagle-6.12/dt"
BOOT_DTB_DIR=/boot/dtb/ti

usage() {
  cat >&2 <<USAGE
Usage: $0 [--module-only]

Build/install the Sony IMX415 driver against the RUNNING BeagleY-AI kernel and
compile/install both provisional Arducam B0569 CSI0 DTBO address variants.

This script deliberately does NOT select an address variant and does NOT reboot.
After determining the actual B0569 I2C strap, select it with:
  ti-k3-select-imx415-overlay --address 0x37
or:
  ti-k3-select-imx415-overlay --address 0x1a
then reboot once.

--module-only   build/install imx415.ko but do not compile/install DTBOs
USAGE
  exit 2
}

MODULE_ONLY=no
while (($#)); do
  case "$1" in
    --module-only) MODULE_ONLY=yes; shift ;;
    -h|--help) usage ;;
    *) usage ;;
  esac
done

for cmd in make gcc curl install depmod modinfo uname; do
  command -v "$cmd" >/dev/null || { echo "Missing required command: $cmd" >&2; exit 1; }
done

[[ -d "$KBUILD" ]] || {
  cat >&2 <<MSG
Matching kernel build headers are missing:
  $KBUILD

Install headers for the RUNNING kernel before building IMX415. Do not build
against a different kernel release.
MSG
  exit 1
}

mkdir -p "$WORK"

if grep -q '^CONFIG_VIDEO_IMX415=y$' "/boot/config-$KVER" 2>/dev/null; then
  echo "[module] CONFIG_VIDEO_IMX415=y; driver is built into the running kernel"
elif modinfo -k "$KVER" imx415 >/dev/null 2>&1; then
  echo "[module] imx415 already exists for $KVER; skipping external build"
else
  echo "[module] fetching exact Beagle 6.12.49 IMX415 source ($DRIVER_REF)"
  curl --fail --location --retry 5 "$DRIVER_URL" -o "$WORK/imx415.c"
  cat >"$WORK/Makefile" <<'EOF_MAKE'
obj-m += imx415.o
EOF_MAKE

  echo "[module] building against $KBUILD"
  make -C "$KBUILD" M="$WORK" modules
  [[ -s "$WORK/imx415.ko" ]] || { echo 'imx415.ko was not produced' >&2; exit 1; }

  echo "[module] installing /lib/modules/$KVER/extra/arducam/imx415.ko"
  install -D -m 0644 "$WORK/imx415.ko" "/lib/modules/$KVER/extra/arducam/imx415.ko"
  depmod -a "$KVER"
  modinfo -k "$KVER" imx415 >/dev/null
fi

if [[ "$MODULE_ONLY" == yes ]]; then
  echo 'IMX415 live module install PASS (DTBO install skipped).'
  exit 0
fi

command -v dtc >/dev/null || { echo 'Missing required command: dtc (device-tree-compiler)' >&2; exit 1; }
[[ -f /boot/uEnv.txt ]] || { echo 'Expected BeagleY-AI /boot/uEnv.txt boot scheme was not found.' >&2; exit 1; }
install -d -m 0755 "$BOOT_DTB_DIR"

for suffix in 37 1a; do
  src="$DT_DIR/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-${suffix}.dtso"
  name="k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-${suffix}.dtbo"
  out="$WORK/$name"
  [[ -s "$src" ]] || { echo "Missing overlay source: $src" >&2; exit 1; }
  echo "[dt] compiling $name"
  dtc -@ -I dts -O dtb -o "$out" "$src"
  install -m 0644 "$out" "$BOOT_DTB_DIR/$name"
done

cat <<MSG

IMX415 live prerequisites installed successfully.

Driver:
  $(modinfo -k "$KVER" -n imx415 2>/dev/null || echo 'built-in')

DTBO variants:
  $BOOT_DTB_DIR/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-37.dtbo
  $BOOT_DTB_DIR/k3-am67a-beagley-ai-csi0-arducam-b0569-imx415-1a.dtbo

No boot configuration was changed and no reboot was requested.
Determine the actual B0569 address, then select exactly one overlay with:
  ti-k3-select-imx415-overlay --address 0x37
or:
  ti-k3-select-imx415-overlay --address 0x1a

After selection, inspect /boot/uEnv.txt, then reboot once.
MSG
