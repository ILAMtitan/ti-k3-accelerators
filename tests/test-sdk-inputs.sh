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
firmware_builder="$root/firmware/scripts/build-j722s-r2.sh"
ti_2a_builder="$root/scripts/build-ti-2a-provider-from-psdk.sh"

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
    "$firmware_builder" \
    "$ti_2a_builder" \
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

#
# Official TI PSDK Linux release input.
#
# shellcheck source=/dev/null
source "$linux_manifest"

[[ "${format:-}" == 1 ]]
[[ "${vendor:-}" == Texas_Instruments ]]
[[ "${release:-}" == 11.02.01.03 ]]
[[ "${machine:-}" == j722s-evm ]]
[[ "${image_target:-}" == tisdk-adas-image ]]
[[ "${rootfs_archive:-}" == tisdk-adas-image-j722s-evm.tar.xz ]]
[[ "${rootfs_archive_sha256:-}" == \
   01b8e762db99673108b423e8dcb1e5f2c00bdba17359dcd00600b49db030ded4 ]]
[[ "${archive_strip_components:-}" == 0 ]]

#
# Qualified TI package/object lock.
#
objects=$(awk 'END {print NR}' "$file_lock")
packages=$(awk 'NF {n++} END {print n+0}' "$package_lock")

[[ "$objects" == 511 ]]
[[ "$packages" == 16 ]]

awk -F '\t' '
    NF != 3 { bad=1 }
    $1 == "" || $2 !~ /^\// || $3 == "" { bad=1 }
    END { exit bad }
' "$file_lock"

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

actual_packages=$(
    awk 'NF {print $1}' "$package_lock" |
    sort
)

[[ "$actual_packages" == "$expected_packages" ]]

#
# TI-source EdgeAI compatibility-header overlay.
#
unset format vendor release

# shellcheck source=/dev/null
source "$header_manifest"

[[ "${format:-}" == 1 ]]
[[ "${vendor:-}" == Texas_Instruments ]]
[[ "${release:-}" == 11.02.01.03 ]]
[[ "${header_count:-}" == 32 ]]

[[ "${edgeai_tiovx_modules_commit:-}" == \
   16ea980baf1b9c6549bd5cc33aa94ea9c351eb01 ]]

[[ "${edgeai_tiovx_kernels_commit:-}" == \
   b41bef631fcf037e8cb8b754d9db0d42d9ce3210 ]]

[[ "${edgeai_apps_utils_commit:-}" == \
   5a5a694ae02f0d2e4e39028b847e1c777c465cbf ]]

headers=$(awk 'END {print NR}' "$header_lock")

apps=$(
    awk -F '\t' \
        '$1=="edgeai-apps-utils"{n++} END{print n+0}' \
        "$header_lock"
)

kernels=$(
    awk -F '\t' \
        '$1=="edgeai-tiovx-kernels"{n++} END{print n+0}' \
        "$header_lock"
)

modules=$(
    awk -F '\t' \
        '$1=="edgeai-tiovx-modules"{n++} END{print n+0}' \
        "$header_lock"
)

[[ "$headers" == 32 ]]
[[ "$apps" == 9 ]]
[[ "$kernels" == 7 ]]
[[ "$modules" == 16 ]]

awk -F '\t' '
    NF != 3 { bad=1 }
    $1 == "" || $2 !~ /^\/usr\/include\// { bad=1 }
    $3 !~ /^[0-9a-f]{64}$/ { bad=1 }
    END { exit bad }
' "$header_lock"

[[ -z "$(cut -f2 "$header_lock" | sort | uniq -d)" ]]

#
# Preparation must consume the locked inputs rather than a caller-provided
# extracted rootfs.
#
grep -Fq 'extract-ti-linux-rootfs.sh' "$prepare"
grep -Fq 'import-ti-userspace-locked.sh' "$prepare"
grep -Fq 'import-ti-edgeai-development-headers.sh' "$prepare"

grep -Fq -- '--ti-rootfs-archive' "$prepare"
! grep -Fq -- '--ti-rootfs)' "$prepare"

grep -Fq 'TI_K3_WORKDIR_BASE' "$prepare"
grep -Fq 'FORENSIC_HEADER_STAGING_SANITIZED=PASS' "$prepare"

#
# The historical 32-header copy is not authoritative anymore.
#
[[ ! -e \
    "$root/armbian/userpatches/overlay/usr/local/sbin/ti-k3-validate-ti-edgeai-development-header-provenance" ]]

[[ ! -e \
    "$root/armbian/userpatches/overlay/usr/local/share/ti-k3/ti-edgeai-development-header-sources.txt" ]]

grep -Fq "exclude='/usr/include/***'" "$customize"
grep -Fq \
    "exclude='/usr/share/openhd/ti-edgeai-development-headers.env'" \
    "$customize"
grep -Fq \
    "exclude='/usr/share/openhd/ti-edgeai-development-headers.sha256'" \
    "$customize"

#
# The R2 source-build lane must accept a caller-supplied SDK root. A developer's
# absolute checkout path is not an input contract. Binary identity across two
# checkout locations remains a dynamic qualification measurement.
#
! grep -Fq 'CANONICAL_BUILD_ROOT=' "$firmware_manifest"
! grep -Fq '/home/bart/' "$firmware_manifest"
! grep -Fq 'CANONICAL_BUILD_ROOT' "$firmware_builder"
grep -Fq 'BUILD_LINUX_MPU=yes' "$firmware_manifest"
grep -Fq '"BUILD_LINUX_MPU=$BUILD_LINUX_MPU"' "$firmware_builder"
grep -Fq 'SDK_ROOT_POLICY=caller-supplied' "$firmware_builder"

#
# A source-built TI 2A replacement lane now exists. Until that output is proven
# and integrated, image customization still accepts the historical provider.
# The new builder itself must not consume the historical reference tree or the
# frozen provider hash.
#
grep -Fq 'imaging/ti_2a_wrapper' "$ti_2a_builder"
grep -Fq 'BUILD_LINUX_MPU=yes' "$ti_2a_builder"
grep -Fq 'TI_2A_wrapper_create' "$ti_2a_builder"
grep -Fq 'TI_2A_wrapper_process' "$ti_2a_builder"
grep -Fq 'TI_2A_wrapper_delete' "$ti_2a_builder"
! grep -Fq 'reference/r73341' "$ti_2a_builder"
! grep -Fq '4f7b2acf81511fc0dabf7f61b88b7a7574d153cab435c178b238ecc689e6c567' "$ti_2a_builder"

grep -Fq 'ti-2a-wrapper-provider.env' "$customize"

echo 'PASS: TI SDK source-input, firmware-source, 2A-source, and development-header contract'
