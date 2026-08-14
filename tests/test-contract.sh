#!/usr/bin/env bash
set -Eeuo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
overlay="$root/armbian/userpatches/overlay"

# Every absolute ti-k3 helper referenced by active scripts/services must exist.
mapfile -t refs < <(
  grep -RhoE '/usr/local/sbin/ti-k3-[A-Za-z0-9._-]+' \
    "$root/armbian/userpatches" "$root/prepare-armbian.sh" | sort -u
)
for ref in "${refs[@]}"; do
  rel=${ref#/usr/local/sbin/}
  [[ -f "$overlay/usr/local/sbin/$rel" ]] || {
    echo "Missing active helper referenced by package: $ref" >&2
    exit 1
  }
done

# Generic platform must keep application video policy out of runtime metadata.
runtime="$overlay/usr/local/sbin/ti-k3-build-gstreamer-runtime"
! grep -Eq '^(output|bitrate|gop|wave5_dmabuf_import)=' "$runtime"

# Generic installed paths must not depend on OpenHD staging paths after normalization.
compat="$overlay/usr/local/sbin/ti-k3-build-tiovx-compat-plugin"
grep -Fq '/usr/lib/ti-k3-build-only/ti-2a' "$compat"
! grep -Fq '/usr/lib/openhd-build-only/ti-2a' "$compat"

# TI source-build provenance uses one canonical lowercase SoC identity from the
# R2 manifest through the 2A producer and image consumer. A case mismatch here
# previously rejected a valid source-built provider during image customization.
firmware_manifest="$root/firmware/manifests/j722s-r2.env"
ti_2a_builder="$root/scripts/build-ti-2a-provider-from-psdk.sh"
customize="$root/armbian/userpatches/customize-image.sh"
grep -Fxq 'SOC=j722s' "$firmware_manifest"
grep -Fq 'soc=$SOC' "$ti_2a_builder"
grep -Fq '[[ ${vendor:-} == Texas_Instruments && ${soc:-} == j722s ]]' "$customize"
! grep -Fq '${soc:-} == J722S' "$customize"

# IMX219 service must supply the platform camera contract and depend on the
# qualified accelerator stack.
env="$overlay/etc/ti-k3/accelerators.env"
grep -Fxq 'TI_K3_CAMERA_DCC_VISS=/opt/imaging/imx219/linear/dcc_viss_1920x1080.bin' "$env"
grep -Fxq 'TI_K3_CAMERA_DCC_2A=/opt/imaging/imx219/linear/dcc_2a_1920x1080.bin' "$env"
service="$overlay/etc/systemd/system/ti-k3-imx219-prepare.service"
grep -Fq 'Requires=ti-k3-remoteproc-prepare.service' "$service"
grep -Fq 'Environment="TI_K3_CAMERA_MODE=imx219-ti-isp"' "$service"
grep -Fq 'EnvironmentFile=-/etc/ti-k3/gstreamer.env' "$service"

for gst_consumer in \
  "$overlay/usr/local/sbin/ti-k3-info" \
  "$overlay/usr/local/sbin/ti-k3-self-test" \
  "$overlay/usr/local/sbin/ti-k3-test-imx219"; do
  grep -Fq 'source /etc/ti-k3/gstreamer.env' "$gst_consumer"
done

# The platform target owns generic accelerator bring-up only; cameras remain
# optional consumers.
target="$overlay/etc/systemd/system/ti-k3-accelerators.target"
! grep -Fq 'imx219' "$target"

# Host preparation must not destroy an existing Armbian userpatches tree.
prepare="$root/prepare-armbian.sh"
! grep -Fq 'rm -rf "$build/userpatches"' "$prepare"
grep -Fq 'Refusing to overwrite non-empty' "$prepare"

# The build wrapper intentionally pins the container environment used for the
# qualified image.
builder="$root/build-image.sh"
grep -Fq 'ubuntu:noble@sha256:4fbb8e6a8395de5a7550b33509421a2bafbc0aab6c06ba2cef9ebffbc7092d90' "$builder"
grep -Fq './compile.sh build ti-k3-beagley-ai' "$builder"

# Camera discovery owns the public camera.env refresh and must preserve all
# fields required by consumers.
finder="$overlay/usr/local/sbin/ti-k3-find-camera-devices"
grep -Fq 'TI_K3_CAMERA_DCC_VISS=' "$finder"
grep -Fq 'TI_K3_CAMERA_DCC_2A=' "$finder"
grep -Fq 'TI_K3_CAMERA_CSI_V4L2_IO_MODE=' "$finder"
grep -Fq 'TI_K3_CAMERA_TIOVX_SINK_POOL_SIZE=' "$finder"
grep -Fq 'TI_K3_CAMERA_TIOVX_SRC_POOL_SIZE=' "$finder"

echo 'PASS: TI dependency and ownership contract'
