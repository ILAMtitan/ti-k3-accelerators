#!/usr/bin/env bash
set -Eeuo pipefail
export LC_ALL=C

usage()
{
    cat >&2 <<USAGE
Usage:
  $0 [--ti-rootfs-archive FILE] --ti-rtos-src DIR /path/to/Armbian/build

If --ti-rootfs-archive is omitted, the exact TI PSDK Linux archive recorded
in inputs/ti-linux-j722s-11.02.01.03.env is downloaded and SHA-256 verified.

--ti-rtos-src must point to the matching J722S TI PSDK RTOS source tree.
PSDK_TOOLS_PATH must name the TI compiler/SysConfig tools root.

The application-neutral R2 Main R5/C7x firmware candidate and TI 2A wrapper are
built directly from that supplied PSDK RTOS source tree. No frozen firmware or
2A binary input is accepted by this preparation path.
USAGE
    exit 2
}

ti_archive=
ti_rtos_src=

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
            echo "ERROR: --firmware is no longer accepted; R2 firmware is reconstructed from --ti-rtos-src" >&2
            exit 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            break
            ;;
    esac
done

[[ $# -eq 1 && -n "$ti_rtos_src" ]] || usage
[[ -n ${PSDK_TOOLS_PATH:-} ]] || {
    echo "PSDK_TOOLS_PATH is required when --ti-rtos-src is used" >&2
    exit 1
}

root=$(cd "$(dirname "$0")" && pwd)
build=$(readlink -f "$1")
ti_rtos_src=$(readlink -f "$ti_rtos_src")

linux_manifest="$root/inputs/ti-linux-j722s-11.02.01.03.env"
ti_2a_builder="$root/scripts/build-ti-2a-provider-from-psdk.sh"
firmware_apply="$root/firmware/scripts/apply-j722s-r2.sh"
firmware_stage="$root/firmware/scripts/stage-j722s-r2-source-build.sh"

for required in "$linux_manifest" "$ti_2a_builder" "$firmware_apply" "$firmware_stage"; do
    [[ -s "$required" ]] || {
        echo "Missing required source-build input: $required" >&2
        exit 1
    }
done

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

if [[ -d "$build/userpatches" ]] &&
   find "$build/userpatches" -mindepth 1 -print -quit |
   grep -q .
then
    echo "Refusing to overwrite non-empty $build/userpatches; use a dedicated clean Armbian checkout." >&2
    exit 1
fi

mcu="$ti_rtos_src/vision_apps/platform/j722s/rtos/mcu2_0"
inc="$mcu/concerto_mcu2_0_inc.mak"
drivers_j722s="$mcu/generated/ti_drivers_config_j722s.c"
power_j722s="$mcu/generated/ti_power_clock_config_j722s.c"
drivers_historical="$mcu/generated/ti_drivers_config_openhd.c"
power_historical="$mcu/generated/ti_power_clock_config_openhd.c"

canonical_r2=no
if [[ -s "$drivers_j722s" && -s "$power_j722s" ]] &&
   grep -q 'generated/ti_drivers_config_j722s\.c' "$inc" 2>/dev/null &&
   grep -q 'generated/ti_power_clock_config_j722s\.c' "$inc" 2>/dev/null
then
    canonical_r2=yes
fi

if [[ "$canonical_r2" == yes ]]; then
    echo 'TI_R2_SOURCE_STATE=ALREADY_RECONSTRUCTED_APPLICATION_NEUTRAL'
else
    if [[ -e "$drivers_historical" || -e "$power_historical" ]] ||
       grep -q 'generated/ti_.*_config_openhd\.c' "$inc" 2>/dev/null ||
       grep -q 'OHDBG' "$mcu/main.c" 2>/dev/null
    then
        echo 'ERROR: PSDK RTOS tree is still in the temporary historical OpenHD reproduction state.' >&2
        echo 'Restore the canonical *_j722s.c / J7DBG reconstruction or use a fresh PSDK RTOS tree.' >&2
        exit 1
    fi

    echo 'TI_R2_SOURCE_STATE=APPLYING_APPLICATION_NEUTRAL_RECONSTRUCTION'
    bash "$firmware_apply" "$ti_rtos_src"
fi

work_base=${TI_K3_WORKDIR_BASE:-${TMPDIR:-/tmp}}
mkdir -p "$work_base"
work=$(mktemp -d "$work_base/ti-k3-prepare.XXXXXXXX")

cleanup()
{
    rm -rf "$work"
}
trap cleanup EXIT

firmware_source="$work/firmware-source-build"
ti_2a_source="$work/ti-2a-provider-source"

bash "$firmware_stage" \
    "$ti_rtos_src" \
    "$firmware_source"

[[ -s "$firmware_source/SOURCE-BUILD.env" ]] || {
    echo "R2 firmware source build did not produce provenance metadata" >&2
    exit 1
}

echo 'TI_R2_FIRMWARE_SOURCE_INPUT=PASS'

bash "$ti_2a_builder" \
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
firmware_dst="$build/userpatches/overlay/opt/ti-k3-port/firmware-source-build"
ti_2a_dst="$build/userpatches/overlay/opt/ti-k3-port/ti-2a-provider-source"

mkdir -p "$asset_dst" "$firmware_dst" "$ti_2a_dst"

"$root/scripts/import-ti-userspace-locked.sh" \
    "$rootfs" \
    "$asset_dst"

"$root/scripts/import-ti-edgeai-development-headers.sh" \
    "$asset_dst"

cp -a "$firmware_source/." "$firmware_dst/"
cp -a "$ti_2a_source/." "$ti_2a_dst/"

if find "$firmware_dst" \( -type f -o -type l \) \
    \( -name 'libti_2a_wrapper.a' -o -name 'libti_2a_wrapper.so' -o -name 'libti_2a_wrapper.so.*' \) \
    -print -quit | grep -q .
then
    echo "Source-built firmware staging illegally contains a TI 2A wrapper provider" >&2
    exit 1
fi

if find "$firmware_dst" -path '*/usr/include/*' -print -quit | grep -q .; then
    echo "Source-built firmware staging illegally contains development headers" >&2
    exit 1
fi

echo 'SOURCE_FIRMWARE_STAGING_BOUNDARY=PASS'
echo 'TI_K3_ARMBIAN_INPUT_PREPARATION=PASS'
echo "Prepared TI K3 accelerator userpatches in $build/userpatches"
echo "Build: cd $build && ./compile.sh build ti-k3-beagley-ai"
