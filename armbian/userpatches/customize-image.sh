#!/usr/bin/env bash
set -Eeuo pipefail
BOARD=${3:-${BOARD:-}}
ARCH=${5:-${ARCH:-}}
[[ $BOARD == beagley-ai ]] || exit 0
[[ $ARCH == arm64 ]] || { echo 'TI K3 BeagleY-AI requires arm64' >&2; exit 1; }
export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y --no-install-recommends \
  ca-certificates git curl rsync build-essential cmake meson ninja-build pkg-config python3 patch xz-utils \
  libgstreamer1.0-dev libgstreamer-plugins-base1.0-dev libv4l-dev device-tree-compiler \
  gstreamer1.0-tools gstreamer1.0-plugins-base gstreamer1.0-plugins-good gstreamer1.0-plugins-bad \
  gstreamer1.0-plugins-ugly gstreamer1.0-libav v4l-utils bc libelf-dev jq kmod util-linux
install -d -m 1777 /tmp
install -d -m 0755 /etc/ti-k3 /var/lib/ti-k3 /var/lib/ti-k3-validation/boots /run/ti-k3 /opt/ti-k3-src
rsync -a --keep-dirlinks /tmp/overlay/ /

asset_root=/opt/ti-k3-port/ti-assets-rootfs
firmware_root=/opt/ti-k3-port/forensic-firmware
ti_2a_source_root=/opt/ti-k3-port/ti-2a-provider-source
[[ -d $asset_root && -d $firmware_root && -d $ti_2a_source_root ]] || { echo 'TI K3 staged inputs are absent' >&2; exit 1; }
# TI Linux userspace is a filtered staging tree produced by the locked TI SDK input workflow.
# Never import core distribution libraries.
forbidden_re='/(ld-linux-aarch64\.so(\.1)?|libc\.so|libc\.so\.|libstdc\+\+\.so|libgcc_s\.so|libgstreamer-1\.0\.so|libglib-2\.0\.so|libgobject-2\.0\.so|libgio-2\.0\.so|libsystemd\.so)'
if find "$asset_root" \( -type f -o -type l \) -print | grep -E "$forbidden_re" >/dev/null; then
  echo 'TI userspace staging contains forbidden distribution-core libraries' >&2; exit 1
fi
if find "$asset_root" -name 'vx_app_rtos_linux_*.out' -print -quit | grep -q .; then
  echo 'TI Linux userspace staging illegally contains Vision Apps firmware' >&2; exit 1
fi
# Accept either the original R7.33.4.1 provenance filename or later genericized staging.
meta=$(find "$asset_root" -maxdepth 1 -type f \( -name '.openhd-ti-vendor-bundle.env' -o -name '.ti-k3-vendor-bundle.env' \) -print -quit)
[[ -s $meta ]] || { echo 'TI release-bundle provenance missing' >&2; exit 1; }
cp -a "$meta" /var/lib/ti-k3/ti-release-bundle.env
rsync -a --keep-dirlinks --exclude='/.openhd-ti-vendor-bundle.env' --exclude='/.ti-k3-vendor-bundle.env' "$asset_root/" /
ldconfig

# Frozen hardware-validated firmware contract. This remains the only frozen
# binary input during the transition to a fully source-built R2 firmware lane.
source "$firmware_root/SOURCE-BUILD.env"
[[ ${format:-} == 3 && ${build_mode:-} == forensic-july29-baseline ]] || { echo 'Invalid forensic firmware staging' >&2; exit 1; }
[[ ${soc:-} == j722s && ${memory_map_id:-} == openhd-j722s-4gb-evm-matched-v2 ]] || { echo 'Unexpected J722S memory contract' >&2; exit 1; }
[[ ${main_r5_sha256:-} == 214ee24d51bd8f3166cd930b2ed01f058fe5268bc93c4fdbb43feb551f9a753c ]]
[[ ${c71_0_sha256:-} == fcfd8a387e93fb23a7ddae7c8c86283ef9384dad473700012333b2715709be01 ]]
[[ ${c71_1_sha256:-} == 23d2c02c0eba51bfa42c64d36ee6bfdeb8a79be9adc4bfb4d0e3799706bb7116 ]]
cp -a "$firmware_root/SOURCE-BUILD.env" /var/lib/ti-k3/vision-apps-source-build.env
cp -a "$firmware_root/FIRMWARE-MEMORY-MAP-VERIFICATION.json" /var/lib/ti-k3/
cp -a "$firmware_root/FIRMWARE-CONTRACT-VERIFICATION.json" /var/lib/ti-k3/
rsync -a --keep-dirlinks \
  --exclude='/SOURCE-BUILD.env' --exclude='/SHA256SUMS' \
  --exclude='/FIRMWARE-MEMORY-MAP-VERIFICATION.json' --exclude='/FIRMWARE-CONTRACT-VERIFICATION.json' \
  --exclude='/FORENSIC-MCU2-POWER-CLOCK.patch' --exclude='/FORENSIC-MCU2-DRIVERS.patch' \
  --exclude='/usr/include/***' \
  --exclude='/usr/share/openhd/ti-edgeai-development-headers.env' \
  --exclude='/usr/share/openhd/ti-edgeai-development-headers.sha256' \
  "$firmware_root/" /

# TI 2A wrapper provider reconstructed from the supplied PSDK RTOS imaging
# source. This is deliberately staged into a build-only directory and is the
# only location searched by the TIOVX compatibility build.
ti_2a_meta="$ti_2a_source_root/SOURCE-BUILD.env"
[[ -s $ti_2a_meta ]] || { echo 'TI 2A source-build provenance missing' >&2; exit 1; }
# shellcheck source=/dev/null
source "$ti_2a_meta"
[[ ${format:-} == 1 ]] || { echo 'Invalid TI 2A source-build metadata format' >&2; exit 1; }
[[ ${build_mode:-} == ti-psdk-rtos-source-built-2a-provider ]] || { echo 'TI 2A provider is not source-built from PSDK RTOS' >&2; exit 1; }
[[ ${vendor:-} == Texas_Instruments && ${soc:-} == J722S ]] || { echo 'Unexpected TI 2A source-build identity' >&2; exit 1; }
[[ ${provider_kind:-} == static || ${provider_kind:-} == shared ]] || { echo 'Invalid TI 2A provider kind' >&2; exit 1; }
[[ ${provider_filename:-} == libti_2a_wrapper.a || ${provider_filename:-} == libti_2a_wrapper.so ]] || { echo 'Unexpected TI 2A provider filename' >&2; exit 1; }
[[ ${provider_sha256:-} =~ ^[0-9a-f]{64}$ ]] || { echo 'Invalid TI 2A provider SHA-256 provenance' >&2; exit 1; }
ti_2a_provider="$ti_2a_source_root/$provider_filename"
[[ -s $ti_2a_provider ]] || { echo "Missing source-built TI 2A provider: $ti_2a_provider" >&2; exit 1; }
actual_ti_2a_sha=$(sha256sum "$ti_2a_provider" | awk '{print $1}')
[[ $actual_ti_2a_sha == "$provider_sha256" ]] || { echo 'TI 2A source-built provider checksum mismatch' >&2; exit 1; }
install -d -m 0755 /usr/lib/ti-k3-build-only/ti-2a /usr/share/ti-k3
if [[ $provider_kind == static ]]; then
  install -m 0644 "$ti_2a_provider" "/usr/lib/ti-k3-build-only/ti-2a/$provider_filename"
else
  install -m 0755 "$ti_2a_provider" "/usr/lib/ti-k3-build-only/ti-2a/$provider_filename"
fi
cp -a "$ti_2a_meta" /usr/share/ti-k3/ti-2a-wrapper-source-build.env

cat >/etc/ti-k3/vision-apps-firmware.sha256 <<EOF
${main_r5_sha256}  /usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_mcu2_0.out
${c71_0_sha256}  /usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_c7x_1.out
${c71_1_sha256}  /usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_c7x_2.out
EOF
sha256sum -c /etc/ti-k3/vision-apps-firmware.sha256

# Validate compiled DT/memory profile with the standard IMX219 overlay.
base_dtb=$(find /boot/dtb -type f -name 'k3-am67a-beagley-ai.dtb' -print -quit)
camera_dtbo=$(find /boot/dtb -type f -name 'k3-am67a-beagley-ai-csi0-imx219.dtbo' -print -quit)
[[ -s $base_dtb && -s $camera_dtbo ]] || { echo 'BeagleY-AI DTB/IMX219 overlay missing' >&2; exit 1; }
fdtoverlay -i "$base_dtb" -o /tmp/ti-k3-camera-combined.dtb "$camera_dtbo"
/usr/local/sbin/ti-k3-memory-map-verify --dtb /tmp/ti-k3-camera-combined.dtb
for dcc in /opt/imaging/imx219/linear/dcc_viss_1920x1080.bin /opt/imaging/imx219/linear/dcc_2a_1920x1080.bin; do [[ -s $dcc ]] || { echo "Missing DCC: $dcc" >&2; exit 1; }; done

# Build/publish the private TI/GStreamer runtime. If the official TI plugin is
# incomplete, the compatibility plugin must consume the source-built 2A provider
# staged above; no ambient/frozen 2A fallback is allowed.
/usr/local/sbin/ti-k3-build-gstreamer-runtime
rm -rf /usr/lib/ti-k3-build-only /usr/lib/openhd-build-only
ldconfig

# Persist platform identity.
cat >/var/lib/ti-k3/platform.env <<EOF
format=1
soc=j722s
board=beagley-ai
memory_profile=j722s-beagley-ai-4gb-r73341
ti_release=11.02.01.03
firmware_contract=july29-0838-baseline-reconstruction
main_r5_sha256=${main_r5_sha256}
c7x_1_sha256=${c71_0_sha256}
c7x_2_sha256=${c71_1_sha256}
ti_2a_source_build=yes
ti_2a_sha256=${provider_sha256}
remoteproc_sequence=main-r5-endpoint13-then-10s-then-c7x
EOF
systemctl enable ti-k3-accelerators.target
apt-get clean
rm -rf /var/lib/apt/lists/* /opt/ti-k3-port/ti-assets-rootfs /opt/ti-k3-port/forensic-firmware /opt/ti-k3-port/ti-2a-provider-source
printf 'TI K3 accelerator image customization complete\n'
