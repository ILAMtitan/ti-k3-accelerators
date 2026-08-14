#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

usage()
{
    cat >&2 <<USAGE
Usage:
  $0 [--ti-rootfs-archive FILE] --ti-rtos-src DIR --firmware DIR /path/to/Armbian/build

If --ti-rootfs-archive is omitted, the exact TI PSDK Linux archive recorded
in inputs/ti-linux-j722s-11.02.01.03.env is downloaded and SHA-256 verified.

--ti-rtos-src must point to the matching J722S TI PSDK RTOS source tree.
PSDK_TOOLS_PATH must name the TI compiler/SysConfig tools root used to build
an AArch64 TI 2A wrapper provider directly from imaging/ti_2a_wrapper.

--firmware remains the frozen hardware-qualified R2 firmware input for this
transition stage. It will be replaced by the source-built R2 firmware lane
once that firmware cohort is independently qualified.
USAGE
    exit 2
}

ti_archive=
ti_rtos_src=
firmware=

while (($#)); do
    case "$1" in
        --ti-rootfs-archive)
            ti_archive=${2:?}
            shift 2
            ;;
        --ti-rtos-src)
            ti_rtos_src=${2:?}
            shift 2
            ;;
        --firmware)
            firmware=${2:?}
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -eq 1 && -n "$firmware" && -n "$ti_rtos_src" ]] || usage
[[ -n ${PSDK_TOOLS_PATH:-} ]] || {
    echo "PSDK_TOOLS_PATH is required when --ti-rtos-src is used" >&2
    exit 1
}

root=$(cd "$(dirname "$0")" && pwd)
build=$(readlink -f "$1")
firmware=$(readlink -f "$firmware")
ti_rtos_src=$(readlink -f "$ti_rtos_src")

linux_manifest="$root/inputs/ti-linux-j722s-11.02.01.03.env"
ti_2a_builder="$root/scripts/build-ti-2a-provider-from-psdk.sh"

[[ -s "$linux_manifest" ]] || {
    echo "Missing TI Linux release manifest" >&2
    exit 1
}

[[ -x "$ti_2a_builder" ]] || {
    echo "Missing TI 2A source builder: $ti_2a_builder" >&2
    exit 1
}

[[ -d "$ti_rtos_src/sdk_builder" && -d "$ti_rtos_src/imaging/ti_2a_wrapper" ]] || {
    echo "Invalid TI PSDK RTOS source tree: $ti_rtos_src" >&2
    exit 1
}

# shellcheck source=/dev/null
source "$linux_manifest"

[[ "${rootfs_archive_sha256:-}" =~ ^[0-9a-f]{64}$ ]] || {
    echo "Invalid TI Linux release manifest" >&2
    exit 1
}

if ! git -C "$build" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "Not an Armbian Git checkout: $build" >&2
    exit 1
fi

[[ -s "$firmware/SOURCE-BUILD.env" ]] || {
    echo "Missing forensic firmware staging" >&2
    exit 1
}

[[ -s "$firmware/usr/lib/firmware/vision_apps_evm/vx_app_rtos_linux_mcu2_0.out" ]] || {
    echo "Missing qualified Main R5 firmware" >&2
    exit 1
}

for pair in \
 'vx_app_rtos_linux_mcu2_0.out:214ee24d51bd8f3166cd930b2ed01f058fe5268bc93c4fdbb43feb551f9a753c' \
 'vx_app_rtos_linux_c7x_1.out:fcfd8a387e93fb23a7ddae7c8c86283ef9384dad473700012333b2715709be01' \
 'vx_app_rtos_linux_c7x_2.out:23d2c02c0eba51bfa42c64d36ee6bfdeb8a79be9adc4bfb4d0e3799706bb7116'
do
    f=${pair%%:*}
    expected=${pair#*:}

    actual=$(
        sha256sum \
            "$firmware/usr/lib/firmware/vision_apps_evm/$f" |
        awk '{print $1}'
    )

    [[ "$actual" == "$expected" ]] || {
        echo "Firmware hash mismatch: $f" >&2
        exit 1
    }
done

echo 'QUALIFIED_FIRMWARE_INPUT=PASS'

if [[ -d "$build/userpatches" ]] &&
   find "$build/userpatches" -mindepth 1 -print -quit |
   grep -q .
then
    echo "Refusing to overwrite non-empty $build/userpatches; use a dedicated clean Armbian checkout." >&2
    exit 1
fi

work_base=${TI_K3_WORKDIR_BASE:-${TMPDIR:-/tmp}}

mkdir -p "$work_base"

work=$(mktemp -d "$work_base/ti-k3-prepare.XXXXXXXX")

cleanup()
{
    rm -rf "$work"
}
trap cleanup EXIT

ti_2a_source="$work/ti-2a-provider-source"

"$ti_2a_builder" \
    "$ti_rtos_src" \
    "$ti_2a_source"

[[ -s "$ti_2a_source/SOURCE-BUILD.env" ]] || {
    echo "TI 2A source build did not produce provenance metadata" >&2
    exit 1
}

echo 'TI_2A_SOURCE_INPUT=PASS'

if [[ -n "$ti_archive" ]]; then
    ti_archive=$(readlink -f "$ti_archive")

    [[ -s "$ti_archive" ]] || {
        echo "TI rootfs archive not found: $ti_archive" >&2
        exit 1
    }
else
    cache_base=${XDG_CACHE_HOME:-"$HOME/.cache"}
    cache_dir="$cache_base/ti-k3-accelerators"
    mkdir -p "$cache_dir"

    ti_archive="$cache_dir/$rootfs_archive"

    download=yes

    if [[ -s "$ti_archive" ]]; then
        actual=$(sha256sum "$ti_archive" | awk '{print $1}')

        if [[ "$actual" == "$rootfs_archive_sha256" ]]; then
            download=no
            echo 'TI_ROOTFS_CACHE=HIT'
        else
            rm -f "$ti_archive"
        fi
    fi

    if [[ "$download" == yes ]]; then
        command -v curl >/dev/null || {
            echo "curl is required to fetch TI PSDK Linux rootfs" >&2
            exit 1
        }

        temp_archive="$ti_archive.part"
        rm -f "$temp_archive"

        curl \
            --fail \
            --location \
            --retry 5 \
            --connect-timeout 20 \
            "$rootfs_url" \
            -o "$temp_archive"

        actual=$(sha256sum "$temp_archive" | awk '{print $1}')

        [[ "$actual" == "$rootfs_archive_sha256" ]] || {
            rm -f "$temp_archive"
            echo "Downloaded TI rootfs SHA-256 mismatch" >&2
            exit 1
        }

        mv "$temp_archive" "$ti_archive"

        echo 'TI_ROOTFS_DOWNLOAD=PASS'
    fi
fi

rootfs="$work/ti-rootfs"

"$root/scripts/extract-ti-linux-rootfs.sh" \
    "$ti_archive" \
    "$rootfs"

mkdir -p "$build/userpatches"
cp -a "$root/armbian/userpatches/." "$build/userpatches/"

asset_dst="$build/userpatches/overlay/opt/ti-k3-port/ti-assets-rootfs"
firmware_dst="$build/userpatches/overlay/opt/ti-k3-port/forensic-firmware"
ti_2a_dst="$build/userpatches/overlay/opt/ti-k3-port/ti-2a-provider-source"

mkdir -p "$asset_dst" "$firmware_dst" "$ti_2a_dst"

"$root/scripts/import-ti-userspace-locked.sh" \
    "$rootfs" \
    "$asset_dst"

"$root/scripts/import-ti-edgeai-development-headers.sh" \
    "$asset_dst"

cp -a "$firmware/." "$firmware_dst/"
cp -a "$ti_2a_source/." "$ti_2a_dst/"

#
# The historical forensic firmware bundle carried a 32-header EdgeAI
# development snapshot. Those headers are now reconstructed independently
# from pinned TI source repositories and belong to ti-assets-rootfs.
#
rm -rf "$firmware_dst/usr/include"

rm -f \
    "$firmware_dst/usr/share/openhd/ti-edgeai-development-headers.env" \
    "$firmware_dst/usr/share/openhd/ti-edgeai-development-headers.sha256"

if [[ -e "$firmware_dst/usr/include" ]]; then
    echo "Forensic firmware staging still contains development headers" >&2
    exit 1
fi

if [[ -e "$firmware_dst/usr/share/openhd/ti-edgeai-development-headers.env" ||
      -e "$firmware_dst/usr/share/openhd/ti-edgeai-development-headers.sha256" ]]; then
    echo "Forensic firmware staging still contains historical header provenance" >&2
    exit 1
fi

echo 'FORENSIC_HEADER_STAGING_SANITIZED=PASS'

#
# The TI 2A wrapper is now reconstructed from the PSDK RTOS imaging source.
# Remove every historical build-only copy from the frozen firmware staging so
# the Armbian customization can only consume the source-built provider above.
#
rm -rf \
    "$firmware_dst/usr/lib/openhd-build-only/ti-2a" \
    "$firmware_dst/usr/lib/ti-k3-build-only/ti-2a"

rm -f \
    "$firmware_dst/usr/share/openhd/ti-2a-wrapper-provider.env" \
    "$firmware_dst/usr/share/ti-k3/ti-2a-wrapper-provider.env" \
    "$firmware_dst/usr/share/ti-k3/ti-2a-wrapper-source-build.env"

if find "$firmware_dst" \( -type f -o -type l \) \
    \( -name 'libti_2a_wrapper.a' -o -name 'libti_2a_wrapper.so' -o -name 'libti_2a_wrapper.so.*' \) \
    -print -quit | grep -q .
then
    echo "Forensic firmware staging still contains a TI 2A wrapper provider" >&2
    exit 1
fi

echo 'FORENSIC_TI_2A_STAGING_SANITIZED=PASS'
echo 'TI_K3_ARMBIAN_INPUT_PREPARATION=PASS'
echo "Prepared TI K3 accelerator userpatches in $build/userpatches"
echo "Build: cd $build && ./compile.sh build ti-k3-beagley-ai"
