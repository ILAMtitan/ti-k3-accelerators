#!/usr/bin/env bash
set -Eeuo pipefail
usage(){ echo "Usage: $0 /path/to/frozen-ti-linux-rootfs DEST" >&2; exit 2; }
[[ $# -eq 2 ]] || usage
src=$(readlink -f "$1")
dst=$(readlink -m "$2")
[[ -d "$src/usr" ]] || { echo "Invalid TI rootfs staging: $src" >&2; exit 1; }
meta=
for candidate in "$src/.ti-k3-vendor-bundle.env" "$src/.openhd-alpha4-ti-vendor-bundle.env"; do
  [[ -s $candidate ]] && { meta=$candidate; break; }
done
[[ -n $meta ]] || { echo "TI release-bundle provenance missing in $src" >&2; exit 1; }
# Legacy OpenHD-named metadata is accepted only as an immutable frozen input.
# shellcheck source=/dev/null
source "$meta"
[[ "${format:-}" =~ ^[12]$ && "${build_mode:-}" == ti-release-binary ]] || { echo 'Invalid TI release provenance' >&2; exit 1; }
[[ "${release:-}" == 11.02.01.03 && "${machine:-}" == j722s-evm ]] || { echo "Unexpected TI bundle release=${release:-unset} machine=${machine:-unset}" >&2; exit 1; }
[[ "${image_target:-}" == tisdk-adas-image ]] || { echo "Unexpected TI image target: ${image_target:-unset}" >&2; exit 1; }
[[ "${rootfs_archive_sha256:-}" =~ ^[0-9a-f]{64}$ ]] || { echo 'TI provenance lacks archive SHA-256' >&2; exit 1; }

rm -rf "$dst"
mkdir -p "$dst"
copy_path(){
  local p=$1
  [[ -e "$src$p" || -L "$src$p" ]] || return 0
  mkdir -p "$dst$(dirname "$p")"
  cp -a "$src$p" "$dst$p"
}
copy_glob(){
  local pattern=$1 p rel
  shopt -s nullglob
  for p in "$src"$pattern; do
    rel=${p#"$src"}
    mkdir -p "$dst$(dirname "$rel")"
    cp -a "$p" "$dst$rel"
  done
  shopt -u nullglob
}

# Accelerator-specific userspace/data only. Do not import the TI distro wholesale.
copy_path /opt/imaging
copy_path /opt/vision_apps/vx_app_arm_remote_log.out
copy_path /opt/vision_apps/vx_app_arm_ipc.out
copy_path /opt/vision_apps/vision_apps_init.sh
copy_path /usr/share/ti
copy_path /usr/include/processor_sdk

# Non-Vision-Apps media/connectivity firmware used by the TI accelerator runtime.
for firmware_root in /lib/firmware /usr/lib/firmware; do
  copy_glob "$firmware_root/cnm/*"
  copy_glob "$firmware_root/ti-connectivity/*"
  copy_glob "$firmware_root/ti/*"
done

for libroot in /usr/lib /usr/lib64 /usr/lib/aarch64-linux-gnu /usr/local/lib /lib /lib64; do
  copy_path "$libroot/edgeai-tiovx-modules"
  copy_glob "$libroot/libtivx*.so*"
  copy_glob "$libroot/libtiovx*.so*"
  copy_glob "$libroot/libvx*.so*"
  copy_glob "$libroot/libedgeai*.so*"
  copy_glob "$libroot/libapp_utils*.so*"
  copy_glob "$libroot/libapp_remote_log*.so*"
  copy_glob "$libroot/libipc*.so*"
  copy_glob "$libroot/libtivision*.so*"
  copy_glob "$libroot/libti_rpmsg_char*.so*"
  copy_glob "$libroot/libremote_service*.so*"
  copy_glob "$libroot/libgsttiovx-1.0.so*"
  copy_glob "$libroot/gstreamer-1.0/libgsttiovx.so*"
done

# The filtered staging must not contain distribution-core libraries or tools.
forbidden_re='/(ld-linux-aarch64\.so(\.1)?|libc\.so|libc\.so\.|libstdc\+\+\.so|libgcc_s\.so|libgstreamer-1\.0\.so|libglib-2\.0\.so|libgobject-2\.0\.so|libgio-2\.0\.so|libsystemd\.so|usr/bin/sudo$|usr/bin/apt($|-)|usr/bin/dpkg$)'
if find "$dst" \( -type f -o -type l \) -print | grep -E "$forbidden_re" >/dev/null; then
  echo 'Filtered TI accelerator staging contains forbidden distribution files:' >&2
  find "$dst" \( -type f -o -type l \) -print | grep -E "$forbidden_re" >&2 || true
  exit 1
fi

# Remote-core firmware is supplied only by the independent forensic firmware input.
if find "$dst" \( -type f -o -type l \) \( \
    -name 'vx_app_rtos_linux_*.out' -o -name 'j722s-main-r5f0_0-fw' -o \
    -name 'j722s-c71_0-fw' -o -name 'j722s-c71_1-fw' \) -print -quit | grep -q .; then
  echo 'TI userspace import unexpectedly contains Vision Apps remote-core firmware' >&2
  exit 1
fi

[[ -s "$dst/opt/vision_apps/vx_app_arm_remote_log.out" ]] || { echo 'Missing Vision Apps remote logger' >&2; exit 1; }
for dcc in \
  "$dst/opt/imaging/imx219/linear/dcc_viss_1920x1080.bin" \
  "$dst/opt/imaging/imx219/linear/dcc_2a_1920x1080.bin"; do
  [[ -s $dcc ]] || { echo "Missing IMX219 DCC: $dcc" >&2; exit 1; }
done
mapfile -t plugins < <(find "$dst" -type f -path '*/gstreamer-1.0/libgsttiovx.so*' -print | sort -u)
(( ${#plugins[@]} > 0 )) || { echo 'Missing libgsttiovx.so' >&2; exit 1; }
plugin=${plugins[0]}
if command -v readelf >/dev/null 2>&1; then
  hdr=$(readelf -h "$plugin")
  grep -Fq 'Class:                             ELF64' <<<"$hdr" || { echo 'TI GStreamer plugin is not ELF64' >&2; exit 1; }
  grep -Eq 'Machine:[[:space:]]+AArch64' <<<"$hdr" || { echo 'TI GStreamer plugin is not AArch64' >&2; exit 1; }
fi

# Normalize provenance filename at the generic platform boundary.
cp -a "$meta" "$dst/.ti-k3-vendor-bundle.env"

printf 'Filtered TI J722S accelerator userspace staged in %s\n' "$dst"
printf 'TI release=%s machine=%s image=%s\n' "$release" "$machine" "$image_target"
