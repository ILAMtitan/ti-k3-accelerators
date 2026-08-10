#!/usr/bin/env bash
set -Eeuo pipefail
usage(){ echo "Usage: $0 --ti-rootfs DIR --firmware DIR /path/to/Armbian/build" >&2; exit 2; }
ti_rootfs= firmware=
while (($#)); do
  case "$1" in
    --ti-rootfs) ti_rootfs=${2:?}; shift 2;;
    --firmware) firmware=${2:?}; shift 2;;
    -h|--help) usage;;
    *) break;;
  esac
done
[[ $# -eq 1 && -n $ti_rootfs && -n $firmware ]] || usage
root=$(cd "$(dirname "$0")" && pwd)
build=$(readlink -f "$1")
ti_rootfs=$(readlink -f "$ti_rootfs")
firmware=$(readlink -f "$firmware")
[[ -d $build/.git ]] || { echo "Not an Armbian checkout: $build" >&2; exit 1; }
[[ -s $firmware/SOURCE-BUILD.env ]] || { echo "Missing forensic firmware staging" >&2; exit 1; }
[[ -s $firmware/usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_mcu2_0.out ]] || exit 1
for pair in \
 'vx_app_rtos_linux_mcu2_0.out:214ee24d51bd8f3166cd930b2ed01f058fe5268bc93c4fdbb43feb551f9a753c' \
 'vx_app_rtos_linux_c7x_1.out:fcfd8a387e93fb23a7ddae7c8c86283ef9384dad473700012333b2715709be01' \
 'vx_app_rtos_linux_c7x_2.out:23d2c02c0eba51bfa42c64d36ee6bfdeb8a79be9adc4bfb4d0e3799706bb7116'; do
  f=${pair%%:*}; expected=${pair#*:}; actual=$(sha256sum "$firmware/usr/lib/firmware/vision_apps_evm/$f"|awk '{print $1}')
  [[ $actual == $expected ]] || { echo "Firmware hash mismatch: $f" >&2; exit 1; }
done
if [[ -d "$build/userpatches" ]] && find "$build/userpatches" -mindepth 1 -print -quit | grep -q .; then
  echo "Refusing to overwrite non-empty $build/userpatches; use a dedicated clean Armbian checkout." >&2
  exit 1
fi
mkdir -p "$build/userpatches"
cp -a "$root/armbian/userpatches/." "$build/userpatches/"
asset_dst="$build/userpatches/overlay/opt/ti-k3-port/ti-assets-rootfs"
firmware_dst="$build/userpatches/overlay/opt/ti-k3-port/forensic-firmware"
mkdir -p "$asset_dst" "$firmware_dst"
"$root/scripts/import-ti-userspace.sh" "$ti_rootfs" "$asset_dst"
cp -a "$firmware/." "$firmware_dst/"
echo "Prepared TI K3 accelerator userpatches in $build/userpatches"
echo "Build: cd $build && ./compile.sh build ti-k3-beagley-ai"
