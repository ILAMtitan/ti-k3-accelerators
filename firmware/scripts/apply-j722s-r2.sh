#!/usr/bin/env bash
set -Eeuo pipefail

usage()
{
    echo "Usage: $0 <TI-PSDK-RTOS-root>"
    echo
    echo "Example:"
    echo "  $0 /opt/ti/ti-processor-sdk-rtos-j722s-evm-11_02_01_03"
}

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

SDK_ROOT="$(cd "$1" && pwd)"

SCRIPT_DIR="$(
    cd "$(dirname "${BASH_SOURCE[0]}")"
    pwd
)"

REPO_ROOT="$(
    cd "$SCRIPT_DIR/../.."
    pwd
)"

PATCH_DIR="$REPO_ROOT/firmware/patches/j722s-r2"
RTOS_ROOT="$SDK_ROOT/vision_apps/platform/j722s/rtos"
IDENTITY_NORMALIZER="$SCRIPT_DIR/normalize-j722s-r2-qualified-identity.sh"

if [[ ! -d "$RTOS_ROOT" ]]; then
    echo "ERROR: J722S Vision Apps RTOS tree not found:"
    echo "  $RTOS_ROOT"
    exit 1
fi

if [[ ! -f "$IDENTITY_NORMALIZER" ]]; then
    echo "ERROR: missing R5 identity normalizer:"
    echo "  $IDENTITY_NORMALIZER"
    exit 1
fi

PATCHES=(
    "$PATCH_DIR/0001-shared-ddr-memory-map.patch"
    "$PATCH_DIR/0002-main-r5-j722s.patch"
    "$PATCH_DIR/0003-c7x-ddr-identity-map.patch"
)

echo '===== J722S SPLIT-R2 SOURCE RECONSTRUCTION ====='
echo "SDK_ROOT=$SDK_ROOT"
echo

for patch in "${PATCHES[@]}"
do
    if [[ ! -f "$patch" ]]; then
        echo "ERROR: missing patch:"
        echo "  $patch"
        exit 1
    fi

    echo "CHECK $(basename "$patch")"

    git -C "$SDK_ROOT" apply \
        --check \
        --whitespace=nowarn \
        "$patch"
done

echo

for patch in "${PATCHES[@]}"
do
    echo "APPLY $(basename "$patch")"

    git -C "$SDK_ROOT" apply \
        --whitespace=nowarn \
        "$patch"
done

echo
echo '===== QUALIFIED R5 LOAD-IMAGE IDENTITY ====='
bash "$IDENTITY_NORMALIZER" "$SDK_ROOT"

echo
echo '===== POST-APPLY PATCH STATE ====='

for patch in "${PATCHES[@]}"
do
    # The identity normalization intentionally renames two generated source
    # files and changes diagnostic strings after patch application, so only
    # the unchanged portions of the source reconstruction remain directly
    # reverse-checkable. Validate the final contract explicitly below instead.
    if [[ "$(basename "$patch")" == "0002-main-r5-j722s.patch" ]]; then
        echo "NORMALIZED $(basename "$patch")"
        continue
    fi

    git -C "$SDK_ROOT" apply \
        --reverse \
        --check \
        --whitespace=nowarn \
        "$patch"

    echo "APPLIED $(basename "$patch")"
done

echo
echo '===== REQUIRED ADDED FILES ====='

for file in \
    "$RTOS_ROOT/mcu2_0/generated/ti_drivers_config_openhd.c" \
    "$RTOS_ROOT/mcu2_0/generated/ti_power_clock_config_openhd.c"
do
    if [[ -f "$file" ]]; then
        echo "PRESENT ${file#"$SDK_ROOT/"}"
    else
        echo "ERROR: missing ${file#"$SDK_ROOT/"}"
        exit 1
    fi
done

if grep -q 'J7DBG' \
    "$RTOS_ROOT/mcu2_0/main.c" \
    "$RTOS_ROOT/mcu2_0/generated/ti_drivers_config_openhd.c" \
    "$RTOS_ROOT/mcu2_0/generated/ti_power_clock_config_openhd.c"
then
    echo "ERROR: stale J7DBG marker remains in active R5 sources"
    exit 1
fi

echo
echo '===== C7X NO-BOARD-DEPS SYMLINKS ====='

for core in c7x_1 c7x_2
do
    link="$RTOS_ROOT/$core/freertos_no_board_deps.syscfg"

    if [[ ! -L "$link" ]]; then
        echo "ERROR: not a symlink:"
        echo "  $link"
        exit 1
    fi

    target="$(readlink "$link")"

    if [[ "$target" != "freertos.syscfg" ]]; then
        echo "ERROR: unexpected symlink target:"
        echo "  $link -> $target"
        exit 1
    fi

    echo "$core -> $target"
done

echo
echo "J722S_R2_PATCH_APPLY=PASS"
