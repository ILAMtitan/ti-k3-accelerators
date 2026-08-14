#!/usr/bin/env bash
set -eu

root="$(cd "$(dirname "$0")/.." && pwd)"
ext="$root/armbian/userpatches/extensions/waveshare-5dsi.sh"
config="$root/armbian/userpatches/config-ti-k3-beagley-ai-waveshare.conf"
patch="$root/armbian/userpatches/kernel/archive/k3-beagle-6.12/0007-waveshare-5dsi-build-hooks.patch"
dt="$root/armbian/userpatches/waveshare-5dsi/kernel/arch/arm64/boot/dts/ti/k3-am67a-beagley-ai-waveshare-5dsi-continuous.dtso"

bash -n "$ext"
bash -n "$root/build-display-image.sh"
grep -q '^RELEASE="noble"$' "$config"
grep -q '^BUILD_DESKTOP="yes"$' "$config"
grep -q '^DESKTOP_ENVIRONMENT="xfce"$' "$config"
grep -q 'ENABLE_EXTENSIONS="ti-k3-accelerators waveshare-5dsi"' "$config"
grep -q 'custom_kernel_config__waveshare_5dsi_kernel' "$ext"
! grep -q 'kernel_copy_extra_sources__waveshare_5dsi' "$ext"
grep -q 'qualification_status=unqualified_display_candidate' "$ext"
grep -q 'k3-am67a-beagley-ai-waveshare-5dsi-continuous.dtb' "$patch"
grep -q 'idle-state = <0>' "$dt"
grep -q 'waveshare,continuous-clock' "$dt"
! grep -Rqs 'k3-j722s-edgeai-apps\|edgeai-waveshare' \
    "$ext" "$patch" "$dt" "$config"

echo 'PASS: Waveshare display candidate preserves TI K3 platform boundary'
