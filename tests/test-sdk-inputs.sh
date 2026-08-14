#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

root=$(cd "$(dirname "$0")/.." && pwd)

linux_manifest="$root/inputs/ti-linux-j722s-11.02.01.03.env"
file_lock="$root/inputs/ti-j722s-11.02.01.03-userspace-files.lock"
package_lock="$root/inputs/ti-j722s-11.02.01.03-userspace-packages.lock"
header_manifest="$root/inputs/ti-edgeai-development-headers.env"
header_lock="$root/inputs/ti-edgeai-development-headers.lock"
firmware_manifest="$root/firmware/manifests/j722s-r2.env"
firmware_apply="$root/firmware/scripts/apply-j722s-r2.sh"
firmware_builder="$root/firmware/scripts/build-j722s-r2.sh"
firmware_stage="$root/firmware/scripts/stage-j722s-r2-source-build.sh"
firmware_patch="$root/firmware/patches/j722s-r2/0002-main-r5-j722s.patch"
ti_2a_builder="$root/scripts/build-ti-2a-provider-from-psdk.sh"
ti_2a_compat="$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-build-tiovx-compat-plugin"

extractor="$root/scripts/extract-ti-linux-rootfs.sh"
userspace_importer="$root/scripts/import-ti-userspace-locked.sh"
header_importer="$root/scripts/import-ti-edgeai-development-headers.sh"
prepare="$root/prepare-armbian.sh"
customize="$root/armbian/userpatches/customize-image.sh"

for f in \
    "$linux_manifest" \
    "$file_lock" \
    "$package_lock" \
    "$header_manifest" \
    "$header_lock" \
    "$firmware_manifest" \
    "$firmware_apply" \
    "$firmware_builder" \
    "$firmware_stage" \
    "$firmware_patch" \
    "$ti_2a_builder" \
    "$ti_2a_compat" \
    "$extractor" \
    "$userspace_importer" \
    "$header_importer" \
    "$prepare" \
    "$customize"
do
    [[ -s "$f" ]] || {
        echo "Missing TI SDK input-contract file: $f" >&2
        exit 1
    }
done

[[ ! -e "$root/firmware/scripts/normalize-j722s-r2-qualified-identity.sh" ]]

# Official TI PSDK Linux release input.
# shellcheck source=/dev/null
source "$linux_manifest"
[[ "${format:-}" == 1 ]]
[[ "${vendor:-}" == Texas_Instruments ]]
[[ "${release:-}" == 11.02.01.03 ]]
[[ "${machine:-}" == j722s-evm ]]
[[ "${image_target:-}" == tisdk-adas-image ]]
[[ "${rootfs_archive:-}" == tisdk-adas-image-j722s-evm.tar.xz ]]
[[ "${rootfs_archive_sha256:-}" == 01b8e762db99673108b423e8dcb1e5f2c00bdba17359dcd00600b49db030ded4 ]]
[[ "${archive_strip_components:-}" == 0 ]]

# Qualified TI package/object lock.
objects=$(awk 'END {print NR}' "$file_lock")
packages=$(awk 'NF {n++} END {print n+0}' "$package_lock")
[[ "$objects" == 511 ]]
[[ "$packages" == 16 ]]
awk -F '\t' 'NF != 3 { bad=1 } $1 == "" || $2 !~ /^\// || $3 == "" { bad=1 } END { exit bad }' "$file_lock"
[[ -z "$(cut -f2 "$file_lock" | sort | uniq -d)" ]]

expected_packages=$(
cat <<'PACKAGES'
cc33xx-fw
cnm-wave-fw
edgeai-gst-plugins
edgeai-tiovx-kernels
edgeai-tiovx-kernels-dev
edgeai-tiovx-modules
libedgeai-apps-utils-dev
libedgeai-apps-utils0.1.0
libti-rpmsg-char-dev
libti-rpmsg-char0
libtivision-apps-dev
libtivision-apps11.2.0
ti-tidl
ti-tidl-dev
wl18xx-fw
wlconf
PACKAGES
)
actual_packages=$(awk 'NF {print $1}' "$package_lock" | sort)
[[ "$actual_packages" == "$expected_packages" ]]

# TI-source EdgeAI compatibility-header overlay.
unset format vendor release
# shellcheck source=/dev/null
source "$header_manifest"
[[ "${format:-}" == 1 ]]
[[ "${vendor:-}" == Texas_Instruments ]]
[[ "${release:-}" == 11.02.01.03 ]]
[[ "${header_count:-}" == 32 ]]
[[ "${edgeai_tiovx_modules_commit:-}" == 16ea980baf1b9c6549bd5cc33aa94ea9c351eb01 ]]
[[ "${edgeai_tiovx_kernels_commit:-}" == b41bef631fcf037e8cb8b754d9db0d42d9ce3210 ]]
[[ "${edgeai_apps_utils_commit:-}" == 5a5a694ae02f0d2e4e39028b847e1c777c465cbf ]]

headers=$(awk 'END {print NR}' "$header_lock")
apps=$(awk -F '\t' '$1=="edgeai-apps-utils"{n++} END{print n+0}' "$header_lock")
kernels=$(awk -F '\t' '$1=="edgeai-tiovx-kernels"{n++} END{print n+0}' "$header_lock")
modules=$(awk -F '\t' '$1=="edgeai-tiovx-modules"{n++} END{print n+0}' "$header_lock")
[[ "$headers" == 32 ]]
[[ "$apps" == 9 ]]
[[ "$kernels" == 7 ]]
[[ "$modules" == 16 ]]
awk -F '\t' 'NF != 3 { bad=1 } $1 == "" || $2 !~ /^\/usr\/include\// { bad=1 } $3 !~ /^[0-9a-f]{64}$/ { bad=1 } END { exit bad }' "$header_lock"
[[ -z "$(cut -f2 "$header_lock" | sort | uniq -d)" ]]

# Preparation consumes only official/locked source and release inputs.
grep -Fq 'extract-ti-linux-rootfs.sh' "$prepare"
grep -Fq 'import-ti-userspace-locked.sh' "$prepare"
grep -Fq 'import-ti-edgeai-development-headers.sh' "$prepare"
grep -Fq 'build-ti-2a-provider-from-psdk.sh' "$prepare"
grep -Fq 'stage-j722s-r2-source-build.sh' "$prepare"
grep -Fq 'apply-j722s-r2.sh' "$prepare"
grep -Fq -- '--ti-rootfs-archive' "$prepare"
grep -Fq -- '--ti-rtos-src' "$prepare"
! grep -Fq -- '--firmware DIR' "$prepare"
grep -Fq -- '--firmware)' "$prepare"
grep -Fq 'R2 firmware is reconstructed from --ti-rtos-src' "$prepare"
grep -Fq 'TI_K3_WORKDIR_BASE' "$prepare"
grep -Fq 'firmware-source-build' "$prepare"
grep -Fq 'SOURCE_FIRMWARE_STAGING_BOUNDARY=PASS' "$prepare"
grep -Fq 'ti-2a-provider-source' "$prepare"
! grep -Fq 'forensic-firmware' "$prepare"
! grep -Fq 'QUALIFIED_FIRMWARE_INPUT=PASS' "$prepare"
! grep -Fq '214ee24d51bd8f3166cd930b2ed01f058fe5268bc93c4fdbb43feb551f9a753c' "$prepare"
grep -Fq 'ALREADY_RECONSTRUCTED_APPLICATION_NEUTRAL' "$prepare"
grep -Fq 'temporary historical OpenHD reproduction state' "$prepare"

# Historical header/provider artifacts are not active build inputs.
[[ ! -e "$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-validate-ti-edgeai-development-header-provenance" ]]
[[ ! -e "$root/armbian/userpatches/overlay/usr/local/share/ti-k3/ti-edgeai-development-header-sources.txt" ]]
! grep -Fq 'forensic-firmware' "$customize"
! grep -Fq 'FORENSIC-MCU2-' "$customize"
! grep -Fq 'FIRMWARE-MEMORY-MAP-VERIFICATION.json' "$customize"
! grep -Fq 'FIRMWARE-CONTRACT-VERIFICATION.json' "$customize"

# Permanent R2 source reconstruction is application-neutral. The temporary
# historical-name reproduction experiment is evidence only and must never be
# invoked by the active build path.
! grep -Fq 'CANONICAL_BUILD_ROOT=' "$firmware_manifest"
! grep -Fq '/home/bart/' "$firmware_manifest"
! grep -Fq 'CANONICAL_BUILD_ROOT' "$firmware_builder"
grep -Fq 'BUILD_LINUX_MPU=yes' "$firmware_manifest"
grep -Fq '"BUILD_LINUX_MPU=$BUILD_LINUX_MPU"' "$firmware_builder"
grep -Fq 'SDK_ROOT_POLICY=caller-supplied' "$firmware_builder"
grep -Fq 'ti_drivers_config_j722s.c' "$firmware_apply"
grep -Fq 'ti_power_clock_config_j722s.c' "$firmware_apply"
grep -Fq 'R5_TRACE_PREFIX=J7DBG' "$firmware_apply"
! grep -Fq 'normalize-j722s-r2-qualified-identity.sh' "$firmware_apply"
! grep -Fq 'ti_drivers_config_openhd.c' "$firmware_patch"
! grep -Fq 'ti_power_clock_config_openhd.c' "$firmware_patch"

# Source-built firmware staging contains only the new application-neutral
# candidate, its hashes, and provenance. It must remain explicitly unqualified
# until the physical BeagleY-AI qualification gates pass.
grep -Fq 'ti-psdk-rtos-source-built-r2' "$firmware_stage"
grep -Fq 'qualification_status=unqualified_source_candidate' "$firmware_stage"
grep -Fq 'memory_map_id=j722s-beagley-ai-4gb-r73341' "$firmware_stage"
grep -Fq 'r5_driver_basename=ti_drivers_config_j722s.c' "$firmware_stage"
grep -Fq 'r5_power_clock_basename=ti_power_clock_config_j722s.c' "$firmware_stage"
grep -Fq 'r5_trace_prefix=J7DBG' "$firmware_stage"
! grep -Fq 'qualified_runtime_identity=' "$firmware_stage"
grep -Fq 'j722s-main-r5f0_0-fw' "$firmware_stage"
grep -Fq 'j722s-c71_0-fw' "$firmware_stage"
grep -Fq 'j722s-c71_1-fw' "$firmware_stage"
grep -Fq 'J722S_R2_SOURCE_FIRMWARE_STAGING=PASS' "$firmware_stage"
grep -Fq 'firmware-source-build' "$customize"
grep -Fq 'ti-psdk-rtos-source-built-r2' "$customize"
grep -Fq 'unqualified_source_candidate' "$customize"
grep -Fq 'firmware_source_build=yes' "$customize"
grep -Fq 'source-built-r2-application-neutral-candidate' "$customize"
! grep -Fq 'source-built-r2-load-image-equivalent-to-qualified-r2' "$customize"
! grep -Fq 'qualified_r5_driver_basename' "$customize"
! grep -Fq 'qualified_r5_power_clock_basename' "$customize"
! grep -Fq 'qualified_r5_trace_prefix' "$customize"
! grep -Fq 'forensic-july29-baseline' "$customize"
! grep -Fq '214ee24d51bd8f3166cd930b2ed01f058fe5268bc93c4fdbb43feb551f9a753c' "$customize"

# TI 2A provider is source-built and consumed only from its explicit build-only path.
grep -Fq 'imaging/ti_2a_wrapper' "$ti_2a_builder"
grep -Fq 'BUILD_LINUX_MPU=yes' "$ti_2a_builder"
grep -Fq 'TI_2A_wrapper_create' "$ti_2a_builder"
grep -Fq 'TI_2A_wrapper_process' "$ti_2a_builder"
grep -Fq 'TI_2A_wrapper_delete' "$ti_2a_builder"
! grep -Fq 'reference/r73341' "$ti_2a_builder"
! grep -Fq '4f7b2acf81511fc0dabf7f61b88b7a7574d153cab435c178b238ecc689e6c567' "$ti_2a_builder"
grep -Fq 'ti-2a-provider-source' "$customize"
grep -Fq 'ti-2a-wrapper-source-build.env' "$customize"
grep -Fq 'ti_2a_source_build=yes' "$customize"
! grep -Fq 'mv /usr/lib/openhd-build-only/ti-2a' "$customize"
grep -Fq 'TI_2A_SOURCE_DIR=/usr/lib/ti-k3-build-only/ti-2a' "$ti_2a_compat"
grep -Fq 'TI_2A_PROVIDER=$("$ti_2a_helper" "$TI_2A_LINK_DIR" "$TI_2A_SOURCE_DIR")' "$ti_2a_compat"

echo 'PASS: TI SDK application-neutral zero-frozen firmware/2A source-input contract'
